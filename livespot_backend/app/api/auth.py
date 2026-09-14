"""카카오 로그인 + 앱 전용 닉네임 (기능 9 / 2026-09-14 닉네임 후속).

  POST /api/auth/kakao             — 카카오 access token → 검증 → 우리 JWT 발급 (가입도 여기서)
  GET  /api/auth/me                — 우리 JWT → 내 정보 (앱 시작 시 토큰 복원 확인용, P19)
  PUT  /api/auth/me/nickname       — 앱 닉네임 설정/변경 (최초 설정과 변경이 **같은 경로**)
  GET  /api/auth/nickname-available — 입력 중 실시간 중복 확인 (조언일 뿐, 확정은 PUT의 409)

**이 네 개가 "닉네임 없이도 동작해야 하는" 유일한 경로다** — 뒤 셋은
`get_current_user_id_any`를 쓴다(deps.py의 표 참조). 나머지 27개 라우터는
`get_current_user_id`를 그대로 쓰고, 닉네임 미설정이면 403을 받는다(P28).
여기에 다섯 번째를 추가하려 한다면 정말 필요한지 의심할 것 — 닉네임을 정하지 않고도
할 수 있는 일이 늘어날수록 "닉네임 미설정 상태"가 앱 곳곳으로 번진다.

**카카오가 우리에게 주는 값은 회원번호 하나뿐이다**(P34·P38). 닉네임·프로필 이미지
동의항목을 요청하지 않으므로, 이 파일에서 `users` 행의 표시 값을 카카오 값으로 채우는
경로는 **하나도 남아 있지 않다.**

**로그아웃 엔드포인트는 일부러 만들지 않았다.** Q6-A(30일 단일 토큰, refresh 없음)에서
서버는 발급된 토큰을 무효화할 수단이 없다. 그런데도 `POST /auth/logout`을 200만 돌려주도록
만들어 두면, 그 이름을 본 다음 사람이 "서버에서 세션이 끊겼다"고 착각한다. 로그아웃은
클라이언트가 저장된 토큰을 지우는 것이고, 그 사실이 눈에 보이는 편이 정직하다.
(서버 무효화가 필요해지면 토큰에 jti를 넣고 폐기 목록을 두는 별건 작업이 된다.)

가입과 로그인을 나누지 않은 이유(P7): 카카오 계정 하나에 users 행은 하나여야 한다.
경로를 둘로 나누면 "가입인지 로그인인지"를 클라이언트가 판정하게 되고, 잘못 고르면
같은 사람에게 행이 두 개 생겨 크레딧·제보 이력이 갈라진다. 판정은 서버가 한다.
"""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import (
    get_current_user_id_any,
    get_current_user_id_optional,
)
from app.db.models.user import PROVIDER_KAKAO, User
from app.db.session import get_db
from app.models.schemas import (
    AuthUser,
    KakaoLoginRequest,
    LoginResponse,
    NicknameAvailability,
    NicknameUpdateRequest,
)
from app.services import kakao_auth
from app.services.auth_token import create_access_token
from app.services.nickname import ERR_DUPLICATE, validate_nickname

router = APIRouter()


def _to_auth_user(user: User) -> AuthUser:
    """users 행 → 응답 모델. **카카오 회원번호(provider_user_id)는 싣지 않는다**(P4).

    변환을 한 곳에 모아 둔 이유: 로그인 응답과 /me 응답이 같은 모양이어야
    앱이 모델 하나만 갖는다. 두 곳에서 각자 조립하면 언젠가 한쪽에만 필드가 는다.

    **`nickname_required`를 계산하는 곳은 여기 한 곳뿐이다**(P26). 앱은 `nickname == null`을
    직접 해석해 정책을 추론하지 않는다 — 정책이 바뀌면(예: 닉네임 없이도 읽기 외에 뭔가
    허용) 이 한 줄만 고치면 되고, 앱을 다시 배포하지 않아도 된다.
    """
    return AuthUser(
        user_id=user.id,
        nickname=user.nickname,
        nickname_required=user.nickname is None,
        profile_image_url=user.profile_image_url,
        credit_balance=user.credit_balance,
        trust_level=user.trust_level,
        created_at=user.created_at,
    )


@router.post("/kakao", response_model=LoginResponse)
async def login_with_kakao(
    payload: KakaoLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """카카오 access token을 검증하고 우리 JWT를 발급한다.

    **이 엔드포인트만 인증 없이 호출된다.** 인증을 만드는 입구라서 당연하지만, 그래서
    여기 들어온 값은 전부 남의 것일 수 있다고 보고 다룬다 — 클라이언트가 보낸 카카오 ID나
    닉네임을 그대로 믿지 않고, **카카오에 직접 물어본 결과만** 저장한다(P6).
    요청 본문에 kakao_id·nickname을 받지 않는 것도 같은 이유다(받으면 위조 입력 경로가 된다).

    upsert 규칙(P7): (auth_provider='kakao', provider_user_id=카카오 회원번호)로 찾아서
    있으면 그 행을 쓰고, 없을 때만 새 UUID로 만든다. 재로그인해도 user_id가 그대로라
    크레딧·제보가 보존된다(AC4).

    **재로그인은 users 행의 표시 값을 한 글자도 건드리지 않는다**(P23·P39, 2026-09-14).
    예전에는 매 로그인마다 닉네임·프로필 이미지를 카카오 값으로 덮어썼다. 그 결정의 근거는
    "우리 쪽에 프로필 편집 기능이 없으므로 덮어써서 잃을 사용자 입력이 없다"였는데,
    **이번 변경으로 그 전제가 무너졌다** — 이제 닉네임은 사용자가 직접 정한 값이고,
    덮어쓰면 그걸 잃는다. 그래서 갱신 분기 자체를 없앴다(`else`가 남아 있지 않다).
    """
    try:
        kakao_id = await kakao_auth.verify_and_get_kakao_id(payload.kakao_access_token)
    except kakao_auth.KakaoAuthError as e:
        # 사용자의 토큰이 잘못됐다. 다시 로그인하면 풀린다.
        raise HTTPException(status_code=401, detail=str(e)) from e
    except kakao_auth.KakaoUnavailableError as e:
        # 카카오에 닿지 못했다. 다시 눌러도 당장은 안 된다 — 401과 구분해야 앱이 문구를 나눈다.
        raise HTTPException(
            status_code=502,
            detail="카카오 서버와 통신하지 못했습니다. 잠시 후 다시 시도해 주세요.",
        ) from e

    user = await db.scalar(
        select(User).where(
            User.auth_provider == PROVIDER_KAKAO,
            User.provider_user_id == kakao_id,
        )
    )

    is_new_user = user is None
    if user is None:
        # 신규 가입: credit_balance=0, trust_level="NEWCOMER"는 모델 기본값 그대로다(P9).
        # 여기서 크레딧을 얹지 않는다 — 적립은 제보·답변이 저장되는 트랜잭션에서만 일어난다.
        #
        # **nickname=None으로 만든다**(P23·P25). 카카오가 준 이름도, "카카오 사용자" 같은
        # 폴백도 넣지 않는다 — 여기서 아무 값이나 채우면 그 사용자는 닉네임을 **정한 적이
        # 없는데도** nickname_required=false가 되어 설정 화면을 영영 못 본다.
        # profile_image_url도 설정하지 않는다(모델 기본값 None, P39·P40).
        user = User(
            id=str(uuid.uuid4()),
            auth_provider=PROVIDER_KAKAO,
            provider_user_id=kakao_id,
            nickname=None,
        )
        db.add(user)
    # 기존 사용자면 **아무것도 하지 않는다.** else 분기가 없는 것이 이 함수의 계약이다(P39).

    await db.commit()
    await db.refresh(user)

    access_token, expires_at = create_access_token(user.id)
    return LoginResponse(
        access_token=access_token,
        expires_at=expires_at,
        is_new_user=is_new_user,
        user=_to_auth_user(user),
    )


@router.get("/me", response_model=AuthUser)
async def get_me(
    user_id: str = Depends(get_current_user_id_any),
    db: AsyncSession = Depends(get_db),
):
    """저장된 토큰이 아직 쓸 수 있는지 확인하면서 내 정보를 받아온다(P19).

    **`get_current_user_id_any`를 쓴다** — 닉네임 미설정이어도 200이어야 한다(P28 예외).
    앱이 시작할 때 부르는 것이 이 엔드포인트이고, 그 응답의 `nickname_required`를 보고
    닉네임 설정 모달을 띄운다. 여기서 403을 내면 앱은 "닉네임이 필요하다"는 사실 자체를
    알 방법이 없어진다.

    앱은 시작할 때 shared_preferences의 토큰을 복원하고 이걸 한 번 부른다.
    200이면 그대로 로그인 상태를 잇고, **401이면 조용히 로그아웃 상태로 돌아간다**(P20) —
    에러 배너를 띄우지 않는다. 사용자 입장에서는 "한 달 만에 열었더니 다시 로그인"일 뿐이다.

    404가 아니라 401인 이유: 토큰은 유효한데 사용자 행이 사라진 경우도 결국
    "이 자격증명으로는 아무것도 못 한다"이므로, 앱이 분기할 필요가 없다.
    (그 판정은 deps.resolve_user_id_from_token이 이미 한다.)
    """
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다")
    return _to_auth_user(user)


# ──────────────────── 앱 전용 닉네임 (2026-09-14) ────────────────────


@router.get("/nickname-available", response_model=NicknameAvailability)
async def check_nickname_available(
    nickname: str = Query(..., description="확인할 닉네임 (정규화 전 원문)"),
    user_id: str | None = Depends(get_current_user_id_optional),
    db: AsyncSession = Depends(get_db),
):
    """입력 중 실시간 중복 확인 (Q2-B). **조언일 뿐이고 확정이 아니다.**

    확인과 제출 사이에 남이 같은 닉네임을 선점할 수 있으므로, 최종 판정은 언제나
    `PUT /me/nickname`의 409다. 앱은 이 응답으로 입력창 아래 문구만 그린다.
    이 엔드포인트가 있다고 해서 PUT의 409 처리를 생략하면 안 된다.

    **로그인을 요구하지 않는다.** 읽기 경로이고(설계원칙 3), 닉네임은 제보·질문 목록에서
    이미 공개로 표시되는 값이라 새로 새는 정보가 없다. 다만 로그인했다면 **자기 자신의
    현재 닉네임은 available=true**로 본다 — 나중에 닉네임 변경 화면이 붙었을 때
    "지금 쓰는 이름이 사용 불가"라고 뜨는 것을 막는다.

    검증 실패도 200이다(400이 아니다). 타이핑 도중의 두 글자 미만 상태는 **에러가 아니라
    아직 판정할 수 없는 상태**이고, 매 키 입력마다 4xx가 콘솔에 쌓이는 것도 좋지 않다.
    """
    normalized, error = validate_nickname(nickname)
    if error is not None:
        return NicknameAvailability(nickname=normalized, available=False, reason=error)

    # nickname으로 조회하는 유일한 자리다. **사용자를 식별하려는 것이 아니라
    # "이 표시명이 이미 쓰이고 있는가"를 묻는 것이다**(P24 — 식별 키는 여전히 users.id뿐).
    owner_id = await db.scalar(select(User.id).where(User.nickname == normalized))
    if owner_id is not None and owner_id != user_id:
        return NicknameAvailability(
            nickname=normalized, available=False, reason=ERR_DUPLICATE
        )

    return NicknameAvailability(nickname=normalized, available=True, reason=None)


@router.put("/me/nickname", response_model=AuthUser)
async def update_my_nickname(
    payload: NicknameUpdateRequest,
    user_id: str = Depends(get_current_user_id_any),
    db: AsyncSession = Depends(get_db),
):
    """앱 닉네임을 설정한다. **최초 설정과 변경이 같은 엔드포인트다**(2-4절).

    나중에 "닉네임 변경" 화면을 붙일 때 백엔드 작업이 0이 되도록 이렇게 뒀다 —
    변경 UI는 이번 범위가 아니지만(Q4-A), 그 자리를 미리 비워 두는 비용이 0이다.

    응답은 `AuthUser` **전체**다(`/me`와 같은 모양). 성공 후 앱이 `/me`를 다시 부르지
    않아도 되고, 무엇보다 `nickname_required`가 false로 뒤집힌 것을 같은 응답에서 본다.

    ## 실패 처리

    - **400** — 형식 위반. `detail`은 **한국어 문자열**이라 화면에 그대로 띄울 수 있다.
      Pydantic 422(리스트 형식)에 의존하지 않는 이유가 이것이다(schemas.py 참조).
    - **409** — 중복. `detail` 문자열은 `"이미 사용 중인 닉네임이에요"`.
    - **401** — 비로그인. 닉네임 미설정은 **403이 아니다**(여기가 그 상태를 푸는 경로다).

    ## 409를 두 번 판정하는 이유

    사전 SELECT는 **사용자에게 친절한 문구를 주기 위한 것**이고, 실제 방어는
    `IntegrityError` 포착이다. 둘 사이(확인 → 커밋)에 다른 요청이 같은 닉네임을 선점할 수
    있는데 그 창을 SELECT로는 닫을 수 없다 — 닫는 것은 DB의 unique 제약뿐이다.
    사전 SELECT만 두면 경합 시 500이 나가고, IntegrityError만 잡아도 동작은 하지만
    같은 값 재제출(멱등) 판정이 지저분해진다. 그래서 둘 다 둔다.

    ## 같은 값 재제출이 200인 이유 (멱등)

    `bookmarks.py`의 규약과 같다 — "이미 그 상태인 것"을 다시 요청하는 것은 실패가 아니다.
    네트워크가 끊겨 앱이 재시도했을 때 409가 뜨면, 사용자는 **자기가 방금 성공시킨 닉네임을
    남이 쓰고 있다**고 읽는다.
    """
    normalized, error = validate_nickname(payload.nickname)
    if error is not None:
        raise HTTPException(status_code=400, detail=error)

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다")

    if user.nickname == normalized:
        # 멱등: 쓰기도 커밋도 하지 않고 현재 상태를 그대로 돌려준다.
        return _to_auth_user(user)

    owner_id = await db.scalar(select(User.id).where(User.nickname == normalized))
    if owner_id is not None and owner_id != user_id:
        raise HTTPException(status_code=409, detail=ERR_DUPLICATE)

    user.nickname = normalized
    try:
        await db.commit()
    except IntegrityError:
        # uq_users_nickname 위반. 위 SELECT와 이 커밋 사이에 누가 선점했다.
        # rollback하지 않으면 이 세션의 이후 쿼리가 전부 실패한다.
        await db.rollback()
        raise HTTPException(status_code=409, detail=ERR_DUPLICATE)

    await db.refresh(user)
    return _to_auth_user(user)
