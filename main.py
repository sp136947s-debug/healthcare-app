from __future__ import annotations

import math
from typing import Optional
from uuid import uuid4

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import select

from openai import OpenAI

from .config import settings
from .db import Conversation, Feedback, SessionLocal, init_db
from .rag import context_text, retrieve, seed_knowledge

app = FastAPI(title="NIDAN API", version="1.0.0")

origins = ["*"] if settings.cors_origins == "*" else [
    x.strip() for x in settings.cors_origins.split(",") if x.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    session_id: str = Field(default_factory=lambda: str(uuid4()))
    message: str = Field(min_length=1, max_length=6000)
    language: str = "en-IN"


class ChatResponse(BaseModel):
    session_id: str
    answer: str
    emergency: bool = False
    next_step: str = "general"


class FeedbackRequest(BaseModel):
    session_id: str
    rating: int = Field(ge=1, le=5)
    comment: str = ""
    language: str = "en-IN"


class HealthcareRequest(BaseModel):
    latitude: float
    longitude: float
    language: str = "en"


@app.on_event("startup")
def startup() -> None:
    init_db()
    db = SessionLocal()
    try:
        seed_knowledge(db)
    finally:
        db.close()


def detect_emergency(text: str) -> bool:
    emergency_terms = [
        "chest pain", "severe chest", "difficulty breathing", "can't breathe",
        "cannot breathe", "unconscious", "fainted", "heavy bleeding",
        "severe bleeding", "stroke", "seizure", "बेहोश", "सांस नहीं",
        "सांस लेने में दिक्कत", "सीने में तेज दर्द", "बहुत ज्यादा खून",
        "दौरा", "लकवा",
    ]
    low = text.lower()
    return any(term in low for term in emergency_terms)


def local_demo_answer(message: str, language: str, emergency: bool) -> str:
    if emergency:
        if language.startswith("hi"):
            return "यह emergency हो सकती है। अभी नजदीकी emergency department या local emergency service से तुरंत मदद लें। अकेले न रहें।"
        return "This may be an emergency. Please seek immediate help from the nearest emergency department or local emergency service. Do not stay alone."
    if language.startswith("hi"):
        return "मैं आपकी बात समझने में मदद कर सकता हूँ। मैं diagnosis नहीं करता। लक्षण कब से हैं और अभी कितनी परेशानी है, बताइए।"
    return "I can help you understand the next step. I do not diagnose. Tell me when the symptoms started and how severe they are."


@app.get("/health")
def health():
    return {"status": "ok", "service": "nidan-api", "version": "1.0.0"}


@app.post("/chat", response_model=ChatResponse)
def chat(payload: ChatRequest):
    emergency = detect_emergency(payload.message)
    db = SessionLocal()
    try:
        db.add(
            Conversation(
                session_id=payload.session_id,
                role="user",
                language=payload.language,
                message=payload.message,
            )
        )

        rows = retrieve(db, payload.message, top_k=5)
        context = context_text(rows)

        if not settings.openai_api_key:
            answer = local_demo_answer(payload.message, payload.language, emergency)
        else:
            client = OpenAI(api_key=settings.openai_api_key)
            system = f"""
You are NIDAN, a multilingual healthcare navigation assistant for India.

Your job:
- understand the user's problem in simple language;
- provide a safe NEXT STEP, not a diagnosis;
- use the verified knowledge context below;
- reply in the user's requested language when possible;
- use simple Hindi/English or the requested Indian language;
- never invent ABHA status, medical records, facility availability, doctor identity,
  appointment availability, prices, government eligibility, or treatment facts;
- do not prescribe or change medicines;
- if the user describes an emergency, clearly tell them to seek immediate emergency help;
- encourage a qualified clinician when symptoms need examination;
- be concise enough for a voice-first app.

User language: {payload.language}
Emergency flag: {emergency}

Verified knowledge:
{context}
"""
            response = client.responses.create(
                model=settings.openai_model,
                instructions=system,
                input=payload.message,
            )
            answer = response.output_text.strip() or local_demo_answer(
                payload.message, payload.language, emergency
            )

        db.add(
            Conversation(
                session_id=payload.session_id,
                role="assistant",
                language=payload.language,
                message=answer,
            )
        )
        db.commit()

        return ChatResponse(
            session_id=payload.session_id,
            answer=answer,
            emergency=emergency,
            next_step="emergency" if emergency else "guided",
        )
    finally:
        db.close()


@app.post("/feedback")
def feedback(payload: FeedbackRequest):
    db = SessionLocal()
    try:
        db.add(
            Feedback(
                session_id=payload.session_id,
                rating=payload.rating,
                comment=payload.comment,
                language=payload.language,
            )
        )
        db.commit()
        return {"ok": True, "message": "Feedback saved"}
    finally:
        db.close()


@app.get("/healthcare")
async def healthcare(
    latitude: float,
    longitude: float,
    language: str = "en",
):
    # Live results when a Google Places API key is supplied.
    if settings.google_places_api_key:
        body = {
            "includedTypes": [
                "hospital",
                "medical_clinic",
                "doctor",
            ],
            "maxResultCount": 10,
            "rankPreference": "DISTANCE",
            "languageCode": language,
            "regionCode": "IN",
            "locationRestriction": {
                "circle": {
                    "center": {
                        "latitude": latitude,
                        "longitude": longitude,
                    },
                    "radius": 10000.0,
                }
            },
        }
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": settings.google_places_api_key,
            "X-Goog-FieldMask": (
                "places.id,places.displayName,places.formattedAddress,"
                "places.location,places.googleMapsUri,places.nationalPhoneNumber,"
                "places.currentOpeningHours"
            ),
        }
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(
                "https://places.googleapis.com/v1/places:searchNearby",
                json=body,
                headers=headers,
            )
        if response.status_code >= 400:
            raise HTTPException(response.status_code, response.text)

        data = response.json()
        results = []
        for place in data.get("places", []):
            loc = place.get("location", {})
            dist = None
            if "latitude" in loc and "longitude" in loc:
                dist = haversine_km(
                    latitude, longitude,
                    loc["latitude"], loc["longitude"]
                )
            results.append({
                "id": place.get("id"),
                "name": place.get("displayName", {}).get("text", "Healthcare facility"),
                "address": place.get("formattedAddress", ""),
                "phone": place.get("nationalPhoneNumber"),
                "maps_url": place.get("googleMapsUri"),
                "distance_km": round(dist, 2) if dist is not None else None,
                "open_now": (
                    place.get("currentOpeningHours", {}).get("openNow")
                    if place.get("currentOpeningHours") else None
                ),
            })
        return {"source": "Google Places API (New)", "results": results}

    # No fake live data. Tell the client that configuration is required.
    return {
        "source": "not_configured",
        "results": [],
        "message": "Google Places API is not configured. Add GOOGLE_PLACES_API_KEY for live nearby healthcare."
    }


def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))
