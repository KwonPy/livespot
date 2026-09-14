"""요청 → 사용자 식별. **백엔드에서 "이 요청은 누구인가"를 정하는 유일한 지점이다.**

27개 라우터 핸들러가 전부 `Depends(get_current_user_id)` 하나만 본다(P11). 그래서 로그인이
붙어도 그 27곳은 한 줄도 바뀌지 않았다 — 바뀐 것은 이 파일의 본문뿐이다.
같은 판정을 다른 파일에 복사하지 말 것. 유일한 예외가 WebSocket(notifications.py)인데,
브라우저가 WS 핸드셰이크에 커스텀 헤더를 못 싣기 때문이고(P14) 그쪽도 아래
`resolve_user_id_from_token()`을 불러 쓴다.

## 판정 우선순위 (2026-09-14 확정, Q3-A)

  ① `Authorization: Bearer <우리 JWT>` 가 있으면  → 그 토큰이 가리키는 사용자
  ② 없고 `TEST_MODE=true` 면 `X-Test-User-Id`    → 그 테스트 사용자
  ③ 둘 다 없으면                                  → 비로그인(None)

**①이 ②보다 반드시 먼저다.** 순서가 뒤집히면, 개발 환경에서 실제로 로그인한 사용자가
앱에 남아 있던 옛 테스트 헤더 때문에 남의 계정으로 동작한다 — 화면에는 내 닉네임이 뜨는데
제보는 test_user 이름으로 저장되는, 원인을 찾기 어려운 상태가 된다.
그래서 Authorization 헤더가 있으면 **X-Test-User-Id는 존재 자체를 무시한다.**

②가 아직 살아 있는 이유: 기능 6(현장 N명)·기능 8(질문/답변 알림)은 **서로 다른 사용자
둘 이상**이 있어야 검증되는데, 그 유일한 진입점이 테스트유저 전환 드롭다운이다(013·014·015
QA가 전부 이걸로 돌았다). 로그인을 붙이는 김에 그 장치까지 같이 걷어내면, 출품 시연 직전에
검증 수단이 사라진다. 정리는 출품 이후 별건이다.
`TEST_MODE=false`(운영)면 ②는 통째로 꺼지므로 헤더를 보내도 무시된다(AC6, 기존 보장 유지).

## 무효한 자격증명의 처리

토큰이 위조·만료·삭제된 사용자를 가리키면 `get_current_user_id`는 **401**이다(AC3).
403이 아니다 — 권한이 부족한 게 아니라 인증이 성립하지 않은 것이고, 앱은 401을 보고
조용히 로그아웃 상태로 돌아간다(P20).
반면 `get_current_user_id_optional`은 무효 토큰도 **None**으로 떨어뜨린다. 읽기 경로가
"만료된 토큰이 저장돼 있다"는 이유로 화면 전체를 실패시키면 안 되기 때문이다(설계원칙 3).

## 닉네임 미설정 사용자의 처리 (2026-09-14 추가, P28)

앱 전용 닉네임이 도입되면서 **"로그인은 했지만 닉네임을 아직 안 정한" 상태**가 생겼다.
그 상태의 사용자는 **아무것도 쓸 수 없다** — 제보·질문·답변·북마크 전부 403이다.
이유는 단순하다: 작성자 표시 칸에 넣을 이름이 없다.

판정은 **`get_current_user_id` 본문 한 곳**에서만 한다. 27개 라우터 호출부는 한 줄도
바뀌지 않았다(P11 유지). 이 파일 밖에서 `if user.nickname is None:` 분기가 생기기
시작하면 016의 F1·F2·F3(신원 판정이 흩어져 난 버그 3건)를 재현하는 중이라는 신호다.

의존성이 셋으로 늘었다. 고르는 기준:

| 의존성 | 비로그인 | 닉네임 미설정 | 쓰는 곳 |
|---|---|---|---|
| `get_current_user_id_optional` | None | 통과 | 비로그인도 보는 읽기 |
| `get_current_user_id_any`      | 401  | **통과** | 닉네임을 정하러 가는 길목 3개뿐 |
| `get_current_user_id`          | 401  | **403**  | 나머지 전부 |

`get_current_user_id_any`를 쓰는 곳은 `GET /auth/me`, `PUT /auth/me/nickname`,
`GET /auth/nickname-available` **셋뿐이다.** 이 셋까지 403으로 막으면 닉네임을 설정할
방법이 사라져 사용자가 갇힌다(닭과 달걀). 넷째가 생기려 하면 그때 정말 필요한지 의심할 것.

403 본문이 **문자열이 아니라 dict인 것이 계약의 일부다**(P29):
`{"detail": {"code": "NICKNAME_REQUIRED", "message": "..."}}`.
403은 이미 다른 뜻으로 쓰이고 있어서(`questions.py:242,260` 남의 질문/답변 수정 거부,
`reports.py:77` 제보 권한) **상태코드만으로는 구분할 수 없다.** 앱은 `code` 값을 보고
닉네임 설정 시트를 띄운다.
"""

from fastapi import Depends, Header, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.db.models.user import User
from app.services.auth_token import decode_access_token

_UNAUTHORIZED_DETAIL = "로그인이 필요합니다"

# 앱이 이 문자열로 분기한다(P29). 바꾸면 api_service.dart의 분기가 조용히 죽는다.
NICKNAME_REQUIRED_CODE = "NICKNAME_REQUIRED"
NICKNAME_REQUIRED_DETAIL = {
    "code": NICKNAME_REQUIRED_CODE,
    "message": "닉네임을 먼저 설정해 주세요",
}


def _extract_bearer(authorization: str | None) -> str | None:
    """`Authorization: Bearer xxx`에서 토큰만 꺼낸다. 형식이 아니면 None."""
    if not authorization:
        return None
    parts = authorization.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None
    token = parts[1].strip()
    return token or None


async def resolve_user_id_from_token(db: AsyncSession, token: str) -> str | None:
    """토큰 문자열 → user_id. 무효하거나 그 사용자가 이미 없으면 None.

    서명 검증만으로 끝내지 않고 **DB에 실제로 그 행이 있는지까지 본다.** 서명이 맞아도
    사용자가 지워졌으면 그 토큰으로 쓰기를 하면 FK 위반으로 500이 난다 — 401이 정직하다.
    (회원 탈퇴는 이번 범위가 아니지만, 개발 중 DB를 갈아엎는 일이 잦아 실제로 마주친다.)

    notifications.py의 WebSocket도 이 함수를 쓴다 — 그쪽은 헤더를 못 쓰고 쿼리 파라미터로
    같은 토큰을 받을 뿐, **판정 자체는 여기 한 곳뿐이어야 한다.**
    """
    user_id = decode_access_token(token)
    if user_id is None:
        return None
    user = await db.get(User, user_id)
    if user is None:
        return None
    return user_id


async def get_current_user_id_optional(
    authorization: str | None = Header(default=None, alias="Authorization"),
    x_test_user_id: str | None = Header(default=None, alias="X-Test-User-Id"),
    db: AsyncSession = Depends(get_db),
) -> str | None:
    """로그인했으면 user_id, 아니면 None. **비로그인도 볼 수 있는 경로**에서 쓴다.

    "이 사람 것만 표시"류의 곁다리 정보를 읽기 응답에 얹을 때를 위한 자리다
    (예: 관광지 상세에 '내가 북마크했는지'). 지금 이걸 쓰는 라우터는 없다 —
    쓰기·마이페이지는 전부 아래 엄격한 쪽을 쓴다.
    """
    token = _extract_bearer(authorization)
    if token is not None:
        # ① Authorization이 있으면 여기서 끝. 실패해도 ②로 흘러가지 않는다 —
        #    만료된 토큰이 테스트유저 헤더로 조용히 대체되면 그게 더 혼란스럽다.
        return await resolve_user_id_from_token(db, token)

    if settings.TEST_MODE and x_test_user_id:
        # ② 개발 전용. 값을 그대로 믿지 않고 실제 존재하는 행인지 확인한다.
        user = await db.get(User, x_test_user_id)
        if user is not None:
            return x_test_user_id

    return None  # ③ 비로그인


async def get_current_user_id_any(
    user_id: str | None = Depends(get_current_user_id_optional),
) -> str:
    """로그인한 user_id. 아니면 **401**. **닉네임 설정 여부는 보지 않는다.**

    로그인 도입 시점의 `get_current_user_id` 본문 그대로다. 이름을 나눠 둔 이유는
    "닉네임을 정하러 가는 길목"이 닉네임 검사에 막히면 안 되기 때문이다(위 표 참조).
    쓰는 곳은 `GET /auth/me` · `PUT /auth/me/nickname` · `GET /auth/nickname-available` 셋뿐.

    401을 내는 경로 두 가지를 굳이 한 문구로 합친 이유: "토큰이 만료됐다"와 "토큰이 없다"를
    구분해 알려줄 실익이 없고, 앱은 둘 다 똑같이 로그인 유도로 처리한다(AC2·AC3).
    """
    if user_id is None:
        # WWW-Authenticate는 브라우저 기본 인증 팝업을 띄우지 않는 Bearer 스킴으로만 밝힌다.
        raise HTTPException(
            status_code=401,
            detail=_UNAUTHORIZED_DETAIL,
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_id


async def get_current_user_id(
    user_id: str = Depends(get_current_user_id_any),
    db: AsyncSession = Depends(get_db),
) -> str:
    """로그인 + **닉네임 확정**된 user_id. 아니면 401(비로그인) 또는 403(닉네임 미설정).

    반환 타입이 `str`인 것은 로그인 도입 전과 같다(P11) — 27개 호출부가 그대로 동작한다.
    달라진 것은 본문뿐이다. 이것이 이번 변경의 핵심이다: 쓰기 차단이 라우터로 번지지 않는다.

    **추가 쿼리가 사실상 없다.** `resolve_user_id_from_token()`이 이미 같은 요청 안에서
    `db.get(User, user_id)`를 했고, SQLAlchemy identity map에 올라가 있어 여기 재조회는
    SQL을 다시 쏘지 않는다. (TEST_MODE의 `X-Test-User-Id` 경로도 마찬가지다.)

    user가 None인 경우가 403이 아니라 401인 이유: 그건 "권한 부족"이 아니라 자격증명이
    가리키는 행이 사라진 것이다. 위 의존성이 이미 걸러내므로 실제로는 도달하지 않지만,
    나중에 누가 이 함수를 다른 경로에서 부를 때를 대비해 방어한다.
    """
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=401,
            detail=_UNAUTHORIZED_DETAIL,
            headers={"WWW-Authenticate": "Bearer"},
        )
    if user.nickname is None:
        # 문자열이 아니라 dict다(P29). 앱은 detail["code"]로 분기한다.
        raise HTTPException(status_code=403, detail=NICKNAME_REQUIRED_DETAIL)
    return user_id
