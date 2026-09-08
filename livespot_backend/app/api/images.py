"""TourAPI 이미지 CORS 프록시.

왜 필요한가: TourAPI가 내려주는 대표이미지(`firstimage`)는 tong.visitkorea.or.kr 같은
한국관광공사 CDN에 호스팅돼 있는데, 이 호스트들이 Access-Control-Allow-Origin 헤더를
전혀 보내지 않는다. Flutter Web(CanvasKit/Skwasm)의 Image.network는 이미지 바이트를
fetch로 받아오므로 CORS 헤더가 없으면 브라우저가 응답을 차단하고, 앱에서는 아무 에러
없이 회색 placeholder만 남는다(curl로는 200 OK라 "API 키 문제"로 오인하기 쉽다).

우리 서버는 main.py에서 CORSMiddleware(allow_origins=["*"])를 걸어 두었으므로,
이미지를 서버가 대신 받아 그대로 흘려보내면 브라우저가 문제없이 읽는다.

저장하지 않는다: 설계 원칙 2(공공데이터는 실시간 호출)에 따라 DB에도 디스크에도 남기지
않고 매 요청 그대로 중계만 한다. 반복 요청 비용은 브라우저 HTTP 캐시가 흡수한다
(아래 Cache-Control 참고).
"""

import logging
from urllib.parse import urlparse

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse

import aiohttp

from app.services.http_client import get_session

logger = logging.getLogger(__name__)

router = APIRouter()

# SSRF 방지용 화이트리스트. 여기 없는 호스트는 fetch조차 하지 않는다 —
# 임의 URL을 넣어 우리 서버가 내부망(127.0.0.1, 169.254.169.254 등)이나 제3자 서버를
# 대신 호출하게 만들 수 없어야 한다.
#
# 실제로 응답에 등장하는 호스트: tong.visitkorea.or.kr (spots/all의 image_url,
# 상세 firstimage/firstimage2, 갤러리 galWebImageUrl 모두 이 도메인 계열).
# 한국관광공사가 CDN 호스트명을 바꿔도(cdn./cms. 등) 계속 동작하도록 도메인 접미사로
# 허용하되, 접미사는 반드시 앞에 점을 붙여 비교한다 — "evilvisitkorea.or.kr" 같은
# 호스트가 통과하면 화이트리스트가 무의미해진다.
_ALLOWED_HOST_SUFFIXES = (
    ".visitkorea.or.kr",
    ".knto.or.kr",
)
_ALLOWED_HOSTS = {
    "visitkorea.or.kr",
    "tong.visitkorea.or.kr",
}

# 프런트 dio receiveTimeout(8초)보다 먼저 실패를 돌려주기 위해 짧게 건다.
_IMAGE_TIMEOUT = aiohttp.ClientTimeout(total=5, connect=3)

_CHUNK = 64 * 1024


def _is_allowed(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return False
    host = (parsed.hostname or "").lower().rstrip(".")
    if not host:
        return False
    if host in _ALLOWED_HOSTS:
        return True
    return any(host.endswith(suffix) for suffix in _ALLOWED_HOST_SUFFIXES)


@router.get("/proxy")
async def proxy_image(url: str = Query(..., description="원본 이미지 URL (URL 인코딩된 절대 주소)")):
    """화이트리스트에 있는 TourAPI 이미지 CDN의 이미지를 그대로 중계한다.

    400: 화이트리스트 밖 호스트이거나 URL 형식이 아님 (fetch하지 않음)
    404: 원본이 4xx로 응답 (삭제된 이미지 등)
    502: 원본이 5xx이거나 타임아웃/네트워크 실패, 또는 이미지가 아닌 응답
    """
    if not _is_allowed(url):
        raise HTTPException(status_code=400, detail="허용되지 않은 이미지 호스트입니다.")

    session = get_session()
    try:
        resp = await session.get(url, timeout=_IMAGE_TIMEOUT)
    except Exception as e:  # 타임아웃·DNS·연결 실패 — 읽기 경로를 죽이지 않고 명확한 코드로 끝낸다
        logger.warning("image proxy fetch failed: %s (%s)", url, e)
        raise HTTPException(status_code=502, detail="원본 이미지를 가져오지 못했습니다.")

    if resp.status >= 500:
        resp.release()
        raise HTTPException(status_code=502, detail="원본 서버 오류입니다.")
    if resp.status >= 400:
        resp.release()
        raise HTTPException(status_code=404, detail="원본 이미지를 찾을 수 없습니다.")

    content_type = resp.headers.get("Content-Type", "application/octet-stream")
    if not content_type.split(";")[0].strip().lower().startswith("image/"):
        # 화이트리스트 호스트라도 이미지가 아닌 응답(에러 HTML 등)은 중계하지 않는다.
        resp.release()
        raise HTTPException(status_code=502, detail="이미지 응답이 아닙니다.")

    async def _stream():
        try:
            async for chunk in resp.content.iter_chunked(_CHUNK):
                yield chunk
        finally:
            resp.release()

    headers = {
        # 관광지 대표이미지는 거의 바뀌지 않는다. 브라우저가 캐싱하면 재방문 시
        # 프록시를 다시 타지 않는다(서버 측 캐시를 두지 않는 이유이기도 하다).
        "Cache-Control": "public, max-age=86400",
    }
    content_length = resp.headers.get("Content-Length")
    if content_length:
        headers["Content-Length"] = content_length

    return StreamingResponse(_stream(), media_type=content_type, headers=headers)
