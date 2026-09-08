# LiveSpot Backend API

FastAPI backend for LiveSpot application.

## Setup

1. Create a virtual environment and install dependencies:
   ```bash
   python -m venv venv
   source venv/bin/activate  # or venv\Scripts\activate on Windows
   pip install -r requirements.txt
   ```

2. Copy `.env.example` to `.env` and fill in your API keys.

3. Run the development server:
   ```bash
   uvicorn app.main:app --reload
   ```
