# NIDAN — Exact Setup

## A. Install once on the laptop
Install:
1. VS Code
2. Git
3. Flutter SDK + Android SDK
4. Docker Desktop
5. Python 3.12+ (optional for local backend without Docker)

Check:
```bash
flutter doctor
docker --version
git --version
```

## B. Open the project
Extract the ZIP and open the **NIDAN_FULL_VSCODE_READY** folder in VS Code.

## C. Backend
```bash
cd backend
```

Copy `.env.example` to `.env`.

Put your OpenAI key in `.env`:
```env
OPENAI_API_KEY=your_key_here
```

Optional Google Places:
```env
GOOGLE_PLACES_API_KEY=your_google_places_key
```

Start:
```bash
docker compose up --build
```

Test:
- http://localhost:8000/health
- http://localhost:8000/docs

## D. Flutter
Open another VS Code terminal:
```bash
cd mobile
flutter create .
flutter pub get
flutter run
```

For Android Emulator the backend URL is:
`http://10.0.2.2:8000`

For a physical Android phone, open `mobile/lib/config.dart` and change it to your laptop's LAN IP:
`http://192.168.x.x:8000`

## E. GitHub
Before push:
```bash
git init
git add .
git commit -m "NIDAN MVP"
```

Never commit `.env`.

## F. MVP demo
1. Tap BOLEIN.
2. Speak in Hindi/English or another supported language.
3. NIDAN converts speech to text on the phone.
4. Backend retrieves verified knowledge and asks the AI for safe next-step guidance.
5. NIDAN speaks the response.
6. Use Nearby Healthcare to see live Places results when Google Places is configured.
7. Use Feedback after testing.

## Important
ABHA/ABDM live account integration is intentionally not faked. The MVP provides an ABHA help flow and can be connected to official ABDM sandbox/production APIs later when credentials and approved flows are available.
