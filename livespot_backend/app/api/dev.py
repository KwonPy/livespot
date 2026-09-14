"""개발/QA 전용 라우터. **모든 엔드포인트가 TEST_MODE=false면 404다.**

여기 있는 것들은 기능 6(현장 N명)·기능 8(질문/답변 알림)처럼 **사용자가 둘 이상 있어야
검증되는 기능**을 한 기기에서 재현하기 위한 장치다. 카카오 실계정을 여러 개 만들지 않고도
QA가 돌아가게 하는 것이 목적이고, 로그인(기능 9) 도입 후에도 그대로 남겼다(Q3-A).

운영에서 TEST_MODE가 켜지면 **아무나 남의 계정으로 요청할 수 있다.** 404로 가리는 것은
편의일 뿐 보안 경계가 아니다 — 경계는 TEST_MODE 값 그 자체다.
"""

from fastapi import APIRouter, HTTPException
from sqlalchemy import or_, select

from app.config import settings
from app.db.session import AsyncSessionLocal
from app.db.models.user import PROVIDER_TEST, User
from app.db.seed import TEST_USER_ID
from app.models.schemas import LoginResponse
from app.services.auth_token import create_access_token

router = APIRouter()


def _require_test_mode() -> None:
    if not settings.TEST_MODE:
        raise HTTPException(status_code=404, detail="Not found")


@router.get("/test-users")
async def list_test_users():
    """화면에서 test_user/seed_user_*를 골라 여러 사용자의 제보 상황을 시뮬레이션할 수 있도록
    목록을 내려준다.

    2026-09-14(기능 9): 판정 기준이 `firebase_uid.like("seed_user_%")`에서
    `auth_provider == "test"`로 바뀌었다. 컬럼이 정리되면서(마이그레이션 d3a91f7c2b58)
    그 문자열 매칭이 조용히 깨질 자리였다 — 쿼리는 에러 없이 0건을 돌려주고, 드롭다운만
    비어서 원인을 찾기 어려웠을 것이다. **실제 카카오 사용자는 절대 이 목록에 뜨지 않는다.**
    """
    _require_test_mode()

    async with AsyncSessionLocal() as session:
        rows = (
            await session.scalars(
                select(User)
                .where(or_(User.id == TEST_USER_ID, User.auth_provider == PROVIDER_TEST))
                .order_by(User.nickname)
            )
        ).all()
    return [{"id": u.id, "nickname": u.nickname} for u in rows]


@router.post("/login-as/{user_id}", response_model=LoginResponse)
async def login_as_test_user(user_id: str):
    """테스트 사용자로 **진짜 JWT**를 발급받는다 (카카오 없이).

    왜 필요한가: `POST /api/auth/kakao`는 유효한 카카오 access token이 있어야만 토큰을
    발급한다. 그런데 인증 계층 자체(401 경계·WebSocket 토큰·앱의 토큰 저장/복원)를
    검증하려면 **발급된 토큰이 먼저 있어야 한다.** 카카오 키를 기다리는 동안 이 경로가
    없으면 로그인 이후의 모든 것이 검증 불가 상태로 남는다.

    발급되는 토큰은 `/auth/kakao`가 주는 것과 **완전히 동일**하다(같은 서명·같은 수명).
    그래서 이 토큰으로 통과되는 것은 실제 로그인으로도 통과되고, 401이 나는 것은 실제로도 401이다.

    안전장치: ⓐ TEST_MODE=false면 404. ⓑ **auth_provider='test'인 사용자에게만** 발급한다 —
    카카오 사용자 id를 넣어도 거부한다. 이게 없으면 TEST_MODE가 실수로 켜진 순간
    남의 실계정 토큰을 찍어낼 수 있는 문이 된다.
    """
    _require_test_mode()

    async with AsyncSessionLocal() as session:
        user = await session.get(User, user_id)
        if user is None or user.auth_provider != PROVIDER_TEST:
            raise HTTPException(status_code=404, detail="테스트 사용자가 아닙니다")

        access_token, expires_at = create_access_token(user.id)
        from app.api.auth import _to_auth_user  # 순환 import 방지를 위해 지연 import

        return LoginResponse(
            access_token=access_token,
            expires_at=expires_at,
            is_new_user=False,
            user=_to_auth_user(user),
        )
