from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.db.models.user import User
from app.db.seed import TEST_USER_ID


async def get_current_user_id(
    x_test_user_id: str | None = Header(default=None, alias="X-Test-User-Id"),
    db: AsyncSession = Depends(get_db),
) -> str:
    """실제 로그인(기능 1)이 붙기 전까지 쓰는 자리표시자.

    평소에는 항상 TEST_USER_ID로 동작한다. settings.TEST_MODE가 켜져 있을 때만
    (반드시 개발 환경 전용) X-Test-User-Id 헤더로 다른 test_user/seed_user_*를
    지정할 수 있다 — 여러 사용자의 제보 상황을 한 기기에서 재현하기 위함.
    프로덕션에서는 TEST_MODE가 False이므로 헤더를 보내도 무시된다.
    """
    if settings.TEST_MODE and x_test_user_id:
        user = await db.get(User, x_test_user_id)
        if user is not None:
            return x_test_user_id
    return TEST_USER_ID
