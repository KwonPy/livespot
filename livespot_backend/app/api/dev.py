from fastapi import APIRouter, HTTPException
from sqlalchemy import or_, select

from app.config import settings
from app.db.session import AsyncSessionLocal
from app.db.models.user import User
from app.db.seed import TEST_USER_ID

router = APIRouter()


@router.get("/test-users")
async def list_test_users():
    """개발용: 화면에서 test_user/seed_user_*를 골라 여러 사용자의 제보 상황을
    시뮬레이션할 수 있도록 목록을 내려준다. TEST_MODE가 꺼져 있으면(운영) 404."""
    if not settings.TEST_MODE:
        raise HTTPException(status_code=404, detail="Not found")

    async with AsyncSessionLocal() as session:
        rows = (
            await session.scalars(
                select(User)
                .where(or_(User.id == TEST_USER_ID, User.firebase_uid.like("seed_user_%")))
                .order_by(User.nickname)
            )
        ).all()
    return [{"id": u.id, "nickname": u.nickname} for u in rows]
