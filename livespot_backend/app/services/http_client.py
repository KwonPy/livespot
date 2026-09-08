import aiohttp

_session: aiohttp.ClientSession | None = None

# 백엔드가 프런트엔드 dio 타임아웃보다 먼저 실패를 반환하도록 여유를 둠
_TIMEOUT = aiohttp.ClientTimeout(total=8, connect=3)


def get_session() -> aiohttp.ClientSession:
    """이벤트 루프 내에서 재사용되는 공용 aiohttp 세션.

    서비스 인스턴스들이 앱 시작 전 모듈 레벨에서 생성되므로, 세션은
    실제로 처음 필요할 때(이벤트 루프가 돌고 있을 때) 지연 생성한다.

    force_close=True: 서버를 오래 켜두면(--reload로 몇 시간 떠 있는 개발 서버 등) keep-alive로
    재사용하던 연결이 중간에 죽어있는데도 커넥션 풀이 그걸 계속 재사용하려다 connect timeout까지
    통째로 날려버리는 경우가 있었다(TourAPI 호출이 전부 조용히 실패 → 관광지가 지도에서
    통째로 사라지는 것처럼 보임). 매 요청마다 새 연결을 맺게 해 이 문제를 원천 차단한다 —
    TourAPI 호출 빈도가 낮아 매번 새로 연결하는 비용은 무시할 만하다.
    """
    global _session
    if _session is None or _session.closed:
        connector = aiohttp.TCPConnector(force_close=True, enable_cleanup_closed=True)
        _session = aiohttp.ClientSession(timeout=_TIMEOUT, connector=connector)
    return _session


async def close_session() -> None:
    global _session
    if _session is not None and not _session.closed:
        await _session.close()
    _session = None
