from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.user import PROVIDER_TEST, User

# 개발·QA 전용 고정 사용자.
#
# 2026-09-14(기능 9) 이전에는 "로그인이 붙기 전까지 모든 쓰기의 작성자"였다. 이제 로그인이
# 붙었으므로 **평소에는 아무도 이 사용자가 되지 않는다** — TEST_MODE=true + X-Test-User-Id
# 헤더가 있을 때만 쓰인다(deps.py 판정 ②). 그런데도 행을 계속 만드는 이유는 기능 6·8의
# 다인원 QA가 이 사용자와 seed_user_*에 의존하기 때문이다(Q3-A 병존).
# 운영(TEST_MODE=false)에서는 행만 있고 아무도 이 사용자로 요청할 수 없다.
TEST_USER_ID = "00000000-0000-0000-0000-000000000001"


async def ensure_test_user(session: AsyncSession) -> None:
    """test_user 행이 없으면 만든다. 앱 시작 시 1회 호출.

    auth_provider='test'로 만드는 것이 중요하다 — dev.py가 테스트유저 목록을 고를 때
    이 값으로 판정한다(예전에는 firebase_uid 문자열 앞자리로 골랐다).
    """
    existing = await session.get(User, TEST_USER_ID)
    if existing is None:
        session.add(User(
            id=TEST_USER_ID,
            auth_provider=PROVIDER_TEST,
            provider_user_id="test_user",
            nickname="테스트유저",
        ))
        await session.commit()
