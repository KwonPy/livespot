"""카카오 access token 검증 — **신원 확인 전용** (기능 9 / P6, 2026-09-14 축소 P38).

**이 모듈이 카카오에서 가져오는 값은 회원번호 하나뿐이다.** 닉네임도 프로필 이미지도
받지 않는다 — 앱 닉네임은 사용자가 직접 정하고(P23), 프로필 이미지는 동의항목 자체를
요청하지 않기로 확정됐다(P34). 그래서 예전 이름 `fetch_profile()`은 거짓말이 됐고
`verify_and_get_kakao_id()`로 바꿨다(016 9-8의 `firebase_uid` rename과 같은 규칙:
이름이 틀리면 다음 사람이 매번 코드를 읽어야 의미를 알 수 있다).

**동의항목을 전부 껐다고 인증이 약해진 것이 아니다**(P37). `/v2/user/me`의 `id`와
`/v1/user/access_token_info`의 `app_id`는 **동의항목이 아니라 토큰 자체의 속성**이라
동의 없이도 항상 내려온다. 아래 `_verify_app_id()`(다른 카카오 앱 토큰 차단)는
그대로 살아 있고, **지우면 안 된다.**


**이 모듈은 다른 외부 API 서비스(weather.py·gemini.py)와 실패 정책이 반대다.**
그쪽은 읽기 경로라 실패해도 폴백 값을 돌려주지만(설계원칙 3 전반), 여기는 **인증**이다 —
"확인하지 못했으니 일단 통과"는 곧 아무나 남의 계정으로 로그인하는 문이 된다.
그래서 실패는 반드시 예외로 올리고, 라우터가 401/502로 바꾼다.

흐름 (Q1-B):
  프론트가 카카오 JS SDK 팝업으로 **카카오 access token**을 받는다
  → 그 토큰을 우리 서버로 POST
  → (여기) 토큰이 **우리 앱에서 발급된 것인지** 확인 + 사용자 정보 조회
  → 우리 자체 JWT 발급 (auth_token.py)

왜 토큰을 한 번 더 확인하나(access_token_info): /v2/user/me는 "이 토큰이 유효한가"만 보고
"어느 앱의 토큰인가"는 보지 않는다. 그대로 두면 **다른 카카오 앱에서 발급된 토큰**으로도
우리 서비스에 로그인할 수 있다(공격자가 자기 앱에 로그인시킨 피해자의 토큰을 그대로
우리 서버에 제시하면 피해자 계정이 열린다). app_id 대조가 그 문을 닫는다.
settings.KAKAO_APP_ID가 비어 있으면 이 대조를 건너뛰고 경고만 남긴다 — 키 발급 전에도
개발이 가능해야 하기 때문이고, **운영에서는 반드시 채워야 한다.**
"""

import logging

import aiohttp

from app.config import settings
from app.services.http_client import get_session

logger = logging.getLogger(__name__)

_USER_ME_URL = "https://kapi.kakao.com/v2/user/me"
_TOKEN_INFO_URL = "https://kapi.kakao.com/v1/user/access_token_info"

# 사람이 로그인 버튼을 누르고 기다리는 시간이라 상세페이지(8초)보다 짧게 잡는다.
# 앱 receiveTimeout이 8초이므로 두 번 호출(token_info + user_me)해도 그 안에 끝나야 한다.
_TIMEOUT = aiohttp.ClientTimeout(total=4, connect=2)


class KakaoAuthError(Exception):
    """카카오가 토큰을 거부했다 → 사용자 잘못 → 401로 변환한다."""


class KakaoUnavailableError(Exception):
    """카카오 서버에 닿지 못했다 → 우리도 카카오도 잘못이 아님 → 502로 변환한다.

    401과 반드시 구분한다. 이걸 401로 뭉개면 앱이 "다시 로그인하세요"를 띄우는데,
    사용자가 몇 번을 다시 눌러도 되지 않는다(원인이 네트워크이므로).
    """


async def _get_json(url: str, kakao_access_token: str) -> dict:
    """카카오 API GET 공통부. 실패를 종류별로 나눠 올린다."""
    headers = {"Authorization": f"Bearer {kakao_access_token}"}
    try:
        async with get_session().get(url, headers=headers, timeout=_TIMEOUT) as resp:
            if resp.status == 401:
                raise KakaoAuthError("카카오 토큰이 유효하지 않습니다")
            if resp.status != 200:
                body = (await resp.text())[:200]
                logger.warning("카카오 API 비정상 응답 %s %s: %s", url, resp.status, body)
                raise KakaoUnavailableError(f"카카오 응답 코드 {resp.status}")
            return await resp.json()
    except (KakaoAuthError, KakaoUnavailableError):
        raise
    except Exception as e:
        # 타임아웃·DNS·TLS·JSON 파싱 실패 전부 여기로 온다. 인증 실패가 아니다.
        logger.warning("카카오 API 호출 실패 %s: %s", url, e)
        raise KakaoUnavailableError("카카오 서버에 연결하지 못했습니다") from e


async def _verify_app_id(kakao_access_token: str) -> None:
    """토큰이 우리 카카오 앱에서 발급된 것인지 확인한다. KAKAO_APP_ID가 비면 건너뛴다."""
    expected = (settings.KAKAO_APP_ID or "").strip()
    if not expected:
        logger.warning(
            "KAKAO_APP_ID가 비어 있어 토큰의 앱 소유 검증을 건너뜁니다. "
            "운영 배포 전에 .env에 반드시 채우세요 — 다른 카카오 앱의 토큰으로도 로그인이 됩니다."
        )
        return

    data = await _get_json(_TOKEN_INFO_URL, kakao_access_token)
    app_id = str(data.get("app_id", ""))
    if app_id != expected:
        logger.warning("다른 카카오 앱의 토큰이 제시됐습니다 (app_id=%s)", app_id)
        raise KakaoAuthError("이 서비스의 카카오 토큰이 아닙니다")


async def verify_and_get_kakao_id(kakao_access_token: str) -> str:
    """카카오 access token을 검증하고 **회원번호만** 돌려준다 (P38).

    성공하면 그 토큰의 주인이 확실하다. 실패하면 KakaoAuthError(401) 또는
    KakaoUnavailableError(502)를 던진다 — **어떤 경우에도 "모르겠지만 통과"는 없다.**

    돌려주는 회원번호는 `users.provider_user_id`에만 저장되고 **응답에 절대 싣지 않는다**(P4).
    클라이언트가 보는 식별자는 내부 UUID뿐이다.

    닉네임·프로필 이미지 추출 블록은 2026-09-14에 삭제됐다. 동의항목을 요청하지 않으므로
    응답에 아예 오지 않고, 온다 해도 저장할 곳이 없다(앱 닉네임은 사용자가 정한다, P23).
    """
    await _verify_app_id(kakao_access_token)

    data = await _get_json(_USER_ME_URL, kakao_access_token)

    kakao_id = data.get("id")
    if kakao_id is None:
        # 200인데 id가 없으면 우리가 모르는 응답 형식이다. 통과시키면 안 된다.
        logger.warning("카카오 /v2/user/me 응답에 id가 없습니다: %s", str(data)[:200])
        raise KakaoAuthError("카카오 사용자 정보를 확인하지 못했습니다")

    return str(kakao_id)
