from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.user import User

# 실제 로그인(기능 1, 구현순서 7단계)이 붙기 전까지 모든 쓰기 작업의 작성자로 쓰는 고정 사용자.
# function.md 구현 순서: "고정된 test_user 한 명을 하드코딩해서... 로그인은 맨 뒤로 미룬다"
TEST_USER_ID = "00000000-0000-0000-0000-000000000001"


async def ensure_test_user(session: AsyncSession) -> None:
    """test_user 행이 없으면 만든다. 앱 시작 시 1회 호출."""
    existing = await session.get(User, TEST_USER_ID)
    if existing is None:
        session.add(User(
            id=TEST_USER_ID,
            firebase_uid="test_firebase_uid",
            nickname="테스트유저",
        ))
        await session.commit()
