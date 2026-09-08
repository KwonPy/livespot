# LiveSpot 실행 명령어

## 터미널 1 — 백엔드 (FastAPI)
```powershell
cd livespot_backend
.\venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --port 8000
```

## 터미널 2 — 앱 (Flutter, Chrome)
```powershell
cd livespot_app
flutter run -d chrome --web-port=8080
```
