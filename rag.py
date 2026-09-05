import json
from pathlib import Path

from openai import OpenAI
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .db import Knowledge

DATA_FILE = Path(__file__).resolve().parent.parent / "data" / "knowledge.json"


def seed_knowledge(db: Session) -> None:
    if db.scalar(select(Knowledge.id).limit(1)) is not None:
        return

    items = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    client = OpenAI(api_key=settings.openai_api_key) if settings.openai_api_key else None

    for item in items:
        embedding = None
        if client:
            try:
                result = client.embeddings.create(
                    model=settings.openai_embedding_model,
                    input=item["content"],
                )
                embedding = result.data[0].embedding
            except Exception:
                embedding = None

        db.add(
            Knowledge(
                title=item["title"],
                language=item.get("language", "en"),
                content=item["content"],
                source=item["source"],
                embedding=embedding,
            )
        )
    db.commit()


def retrieve(db: Session, query: str, top_k: int = 5) -> list[Knowledge]:
    rows = list(db.scalars(select(Knowledge)).all())

    # Real vector retrieval when embeddings are available.
    if rows and rows[0].embedding is not None and settings.openai_api_key:
        try:
            client = OpenAI(api_key=settings.openai_api_key)
            vector = client.embeddings.create(
                model=settings.openai_embedding_model,
                input=query,
            ).data[0].embedding
            stmt = (
                select(Knowledge)
                .where(Knowledge.embedding.is_not(None))
                .order_by(Knowledge.embedding.cosine_distance(vector))
                .limit(top_k)
            )
            return list(db.scalars(stmt).all())
        except Exception:
            pass

    # Safe local fallback for first-run/demo mode.
    q = query.lower()
    scored = []
    for row in rows:
        score = sum(1 for token in q.split() if token in row.content.lower())
        scored.append((score, row))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [row for score, row in scored[:top_k] if score > 0] or rows[:top_k]


def context_text(rows: list[Knowledge]) -> str:
    return "\n\n".join(
        f"[{r.title}]\n{r.content}\nSource: {r.source}" for r in rows
    )
