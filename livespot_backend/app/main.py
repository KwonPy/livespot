from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.router import api_router
from app.services.http_client import close_session
from app.db.session import engine, AsyncSessionLocal
from app.db.seed import ensure_test_user

app = FastAPI(title="LiveSpot API", description="Backend API for LiveSpot")


@app.on_event("startup")
async def startup_event():
    async with AsyncSessionLocal() as session:
        await ensure_test_user(session)


@app.on_event("shutdown")
async def shutdown_event():
    await close_session()
    await engine.dispose()

# Allow all origins for dev.
# allow_credentials=True와 allow_origins=["*"]는 브라우저가 동시 허용을 거부하는 조합이라 credentials=False로 둠.
# 로그인 토큰은 쿠키가 아니라 Authorization 헤더로 전달되므로 credentials 불필요.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api")

@app.get("/health")
async def health_check():
    return {"status": "ok"}
