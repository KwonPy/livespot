"""자체 발급 JWT의 발급·검증 (기능 9 / Q2-A).

**여기가 "이 요청은 누구인가"의 유일한 진실이다.** deps.py가 이 모듈만 보고 판정하므로,
검증 규칙을 다른 곳에 복사하지 말 것.

왜 Firebase Custom Token이 아닌가(쟁점 A): Firebase가 필요했던 유일한 이유가 FCM 푸시였는데
P21(모바일 웹)·P13(채널 중립 스키마)로 그 이유가 사라졌다. 카카오 검증은 어차피 우리 서버가
하므로 Firebase를 끼워도 인증 강도는 그대로이고, 토큰 종류만 둘로 늘어 디버깅 경로가 하나 더 생긴다.

수명은 settings.AUTH_TOKEN_TTL_DAYS(30일) 하나로 정해진다. refresh 토큰은 없다 —
그 대가(로그아웃해도 서버가 토큰을 무효화하지 못함)와 근거는 config.py 주석에 적어 뒀다.
"""

import logging
from datetime import datetime, timedelta
from typing import Optional, Tuple

import jwt

from app.config import settings

logger = logging.getLogger(__name__)

_ALGORITHM = "HS256"

# 토큰이 우리 서버 것임을 밝히는 값. 다른 서비스의 HS256 토큰이 우연히 같은 시크릿으로
# 검증되는 일을 막는다(시크릿을 공유하는 실수에 대한 2차 방어).
_ISSUER = "livespot"

_DEV_SECRET = "livespot-local-dev-secret-do-not-use-in-production"
_warned_dev_secret = False


def _secret() -> str:
    """서명 키를 돌려주고, 기본값(개발용)이 그대로면 프로세스당 한 번 경고한다.

    기동을 막지 않는 이유: 카카오 키가 없어도 로컬 개발·QA가 굴러가야 하기 때문이다
    (01_spec Q4). 대신 조용히 넘어가지는 않는다 — 이 값이 알려지면 임의 user_id로
    토큰을 위조할 수 있다.
    """
    global _warned_dev_secret
    if settings.JWT_SECRET == _DEV_SECRET and not _warned_dev_secret:
        _warned_dev_secret = True
        logger.warning(
            "JWT_SECRET이 개발용 기본값 그대로입니다. 실서비스 배포 전에 .env의 JWT_SECRET을 "
            "반드시 임의의 긴 문자열로 덮어쓰세요 (예: python -c \"import secrets;print(secrets.token_urlsafe(48))\")."
        )
    return settings.JWT_SECRET


def create_access_token(user_id: str) -> Tuple[str, datetime]:
    """user_id를 담은 토큰과 만료 시각(naive UTC)을 함께 돌려준다.

    만료 시각을 굳이 같이 반환하는 이유: 라우터가 exp를 다시 계산하면 여기와 어긋날 수 있다.
    응답의 expires_at은 반드시 이 값을 그대로 쓴다.
    """
    now = datetime.utcnow()
    expires_at = now + timedelta(days=settings.AUTH_TOKEN_TTL_DAYS)
    payload = {
        "sub": user_id,
        "iss": _ISSUER,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
    }
    token = jwt.encode(payload, _secret(), algorithm=_ALGORITHM)
    return token, expires_at


def decode_access_token(token: str) -> Optional[str]:
    """유효하면 user_id, 아니면 None.

    **예외를 던지지 않고 None으로 뭉갠다.** 호출부(deps.py)가 "왜 무효인지"에 따라 다르게
    행동할 일이 없기 때문이다 — 위조든 만료든 결과는 똑같이 401이고, 사유를 응답에 밝히면
    공격자에게 힌트만 준다. 서버 로그에는 남긴다.

    algorithms를 명시적으로 [HS256]에 고정한 것은 필수다. 생략하면 토큰 헤더의 alg를
    믿게 되어, alg=none 이나 비대칭키 혼동 공격이 열린다.
    """
    try:
        payload = jwt.decode(
            token,
            _secret(),
            algorithms=[_ALGORITHM],
            issuer=_ISSUER,
            options={"require": ["exp", "sub"]},
        )
    except jwt.ExpiredSignatureError:
        logger.info("만료된 토큰으로 요청이 들어왔습니다")
        return None
    except jwt.InvalidTokenError as e:
        logger.info("무효한 토큰으로 요청이 들어왔습니다: %s", type(e).__name__)
        return None

    sub = payload.get("sub")
    if not isinstance(sub, str) or not sub:
        return None
    return sub
