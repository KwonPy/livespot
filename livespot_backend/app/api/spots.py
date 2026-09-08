import asyncio
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from typing import List, Optional
from typing import Dict
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.models.schemas import (
    SpotBase, SpotDetail, SpotIntro,
    BriefingResponse, BriefingBasedOn, CrowdednessInfo, CongestionInfo, PhotoItem,
    NearbyRequest, CongestionBatchRequest, WeatherInfo,
)
from app.services.tour_api import TourAPIService
from app.services.crowdedness import CrowdednessService
from app.services.congestion import CongestionService
from app.services.photo_gallery import PhotoGalleryService
from app.services.weather import WeatherService, unavailable_weather
from app.services.cache import TTLCache
from app.services import report_window
from app.services.gemini import (
    BriefingMaterials,
    GeminiBriefingService,
    build_signature,
    render_no_material,
    render_template,
)

router = APIRouter()

tour_service = TourAPIService()
crowdedness_service = CrowdednessService()
congestion_service = CongestionService()
photo_service = PhotoGalleryService()
weather_service = WeatherService()
gemini_service = GeminiBriefingService()

# 생성된 브리핑의 메모리 캐시. DB 테이블을 만들지 않는다(마이그레이션 없음) — 서버 재시작 시
# 사라져도 다음 요청이 다시 만들면 그만인 파생 데이터다. 캐시 키에 재료 서명이 들어가므로
# 시간이 흘렀다는 이유만으로는 재생성되지 않고, 제보가 1건 늘면 자동으로 새 문장이 나온다.
_briefing_cache = TTLCache()


# ──────────────────── 헬퍼 함수 ────────────────────

def parse_spot(item: dict) -> SpotBase:
    return SpotBase(
        content_id=str(item.get("contentid", "")),
        content_type_id=str(item.get("contenttypeid", "")),
        title=item.get("title", ""),
        address=item.get("addr1", ""),
        image_url=item.get("firstimage", None),
        mapx=float(item.get("mapx") or 0),
        mapy=float(item.get("mapy") or 0),
    )


def parse_spot_detail(item: dict) -> SpotDetail:
    return SpotDetail(
        content_id=str(item.get("contentid", "")),
        content_type_id=str(item.get("contenttypeid", "")),
        title=item.get("title", ""),
        address=item.get("addr1", ""),
        image_url=item.get("firstimage", None),
        mapx=float(item.get("mapx", 0)),
        mapy=float(item.get("mapy", 0)),
        overview=item.get("overview", None),
        homepage=item.get("homepage", None),
        tel=item.get("tel", None),
    )


def parse_spot_intro(item: dict, content_type_id: str) -> SpotIntro:
    """콘텐트타입에 따라 적절한 필드를 매핑"""
    intro = SpotIntro(
        content_id=str(item.get("contentid", "")),
        content_type_id=content_type_id,
    )

    if content_type_id == "12":  # 관광지
        intro.use_time = item.get("usetime", None)
        intro.rest_date = item.get("restdate", None)
        intro.exp_guide = item.get("expguide", None)
        intro.parking = item.get("parking", None)
        intro.charge_info = item.get("usefee", item.get("chkpetleports", None))
    elif content_type_id == "14":  # 문화시설
        intro.use_time = item.get("usetimeculture", None)
        intro.rest_date = item.get("restdateculture", None)
        intro.parking = item.get("parkingculture", None)
        intro.use_fee = item.get("usefee", None)
        intro.spend_time = item.get("spendtime", None)
    elif content_type_id == "15":  # 축제/행사
        intro.event_start_date = item.get("eventstartdate", None)
        intro.event_end_date = item.get("eventenddate", None)
        intro.event_place = item.get("eventplace", None)
        intro.program = item.get("program", None)
        intro.use_fee = item.get("usetimefestival", None)

    return intro


def _filter_allowed_items(items: list) -> list:
    """지역/카테고리 화이트리스트 적용 (nearby, keyword 검색 공통).
    운영 지역 밖 · 음식점/숙박 등 비관광 카테고리 · 좌표 결측 항목을 제외한다."""
    from app.config import settings

    if settings.SERVICE_AREA_FILTER == "seoul":
        items = [item for item in items if "서울" in item.get("addr1", "")]

    ALLOWED_TYPES = {"12", "14", "15", "28", "38"}
    items = [item for item in items if str(item.get("contenttypeid", "")) in ALLOWED_TYPES]

    items = [item for item in items if item.get("mapx") and item.get("mapy")]
    return items


# ──────────────────── 엔드포인트 ────────────────────

@router.get("", response_model=List[SpotBase])
async def list_spots(
    keyword: Optional[str] = None,
    content_type_id: Optional[str] = Query(None, description="콘텐트타입: 12=관광지, 14=문화시설, 15=축제, 25=여행코스, 28=레포츠"),
    page: int = 1,
    num_of_rows: int = 50,
):
    """
    서울 관광지 목록 조회
    - keyword 있으면: searchKeyword2 호출
    - keyword 없으면: areaBasedList2 호출 (서울 기본)
    """
    if keyword:
        items = await tour_service.search_spots(keyword, content_type_id=content_type_id, page=page)
        items = _filter_allowed_items(items)
    else:
        items = await tour_service.get_area_based_list(
            area_code="1",
            content_type_id=content_type_id,
            page=page,
            num_of_rows=num_of_rows,
        )
    return [parse_spot(item) for item in items]


@router.get("/all", response_model=List[SpotBase])
async def all_seoul_spots(num_of_rows: int = 30):
    """
    서울 전체 주요 관광지 조회 (콘텐트타입 12/14/15/25/28 통합)
    앱 초기 로딩 시 사용
    """
    items = await tour_service.get_all_seoul_spots(num_of_rows=num_of_rows)
    return [parse_spot(item) for item in items]


@router.post("/nearby", response_model=List[SpotBase])
async def nearby_spots(req: NearbyRequest):
    """위치 기반 주변 관광지 조회 (locationBasedList2, 거리순 정렬)"""
    # 넉넉하게 가져와서 백엔드에서 필터링 (음식점/카페/숙박 제외)
    items = await tour_service.get_nearby_spots(req.lat, req.lng, req.radius, num_of_rows=100)

    # 지역/카테고리/좌표 필터 적용 (keyword 검색과 동일 정책, _filter_allowed_items 참고)
    items = _filter_allowed_items(items)

    results = []
    for item in items[:20]:  # 필터링된 결과 중 상위 20개만 반환
        spot = parse_spot(item)
        spot.dist = float(item.get("dist", 0)) if item.get("dist") else None
        results.append(spot)
    
    return results


@router.get("/trending", response_model=List[SpotBase])
async def trending_spots():
    """인기 급상승 관광지 (관광지 카테고리 상위 5개)"""
    items = await tour_service.get_area_based_list("1", "12")
    return [parse_spot(item) for item in items[:5]]


@router.post("/congestion-batch", response_model=Dict[str, CongestionInfo])
async def congestion_batch(req: CongestionBatchRequest):
    """
    지도 마커용 — 화면에 보이는 관광지들의 방문 집중률 예측을 한 번에 조회 (기능 9)

    앱이 보낸 관광지들의 주소에서 시군구를 뽑아 중복 없이 호출하므로, 마커 20개에
    실제 API 호출은 보통 1~3회다. 집중률 API는 관광지명으로만 데이터를 구분하는데,
    그 지저분한 이름 매칭은 전부 서버가 처리하고 앱에는 content_id 기준으로 돌려준다
    (설계 원칙 1: 계산은 전부 서버에서).
    """
    spots = [(s.content_id, s.title, s.address) for s in req.spots]
    return await congestion_service.get_congestion_batch(spots)


@router.get("/{content_id}", response_model=SpotDetail)
async def spot_detail(content_id: str):
    """관광지 상세정보 조회 (detailCommon2)"""
    item = await tour_service.get_spot_detail(content_id)
    if not item:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다.")
    return parse_spot_detail(item)


@router.get("/{content_id}/intro", response_model=SpotIntro)
async def spot_intro(content_id: str, content_type_id: str = "12"):
    """
    소개정보 조회 (detailIntro2)
    - 운영시간, 입장료, 주차시설 등
    - content_type_id 필수 (12=관광지, 14=문화시설, 15=축제)
    """
    item = await tour_service.get_spot_intro(content_id, content_type_id)
    if not item:
        raise HTTPException(status_code=404, detail="소개정보를 찾을 수 없습니다.")
    return parse_spot_intro(item, content_type_id)


@router.get("/{content_id}/congestion", response_model=CongestionInfo)
async def spot_congestion(content_id: str):
    """관광지 당일 방문 집중률 예측 조회 (TatsCnctrRateService, 기능 9)

    집중률 API는 관광지명·시군구로만 조회되므로, content_id밖에 없는 상세페이지를 위해
    서버가 먼저 TourAPI에서 제목과 주소를 가져온 뒤 매칭한다. 주소만 있으면 되므로
    서울이 아닌 지역을 검색해서 들어와도 동일하게 동작한다.
    """
    item = await tour_service.get_spot_detail(content_id)
    if not item:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다.")

    return await congestion_service.get_spot_congestion(
        content_id, item.get("title", ""), item.get("addr1")
    )


@router.get("/{content_id}/weather", response_model=WeatherInfo)
async def spot_weather(content_id: str):
    """관광지 현재 날씨 조회 (Open-Meteo)

    앱은 좌표를 보내지 않는다 — HOT SPOTS에서 상세페이지로 진입하는 경로는 Spot.latitude가
    null이라 앱이 좌표를 실을 수 없다. /congestion과 동일하게 서버가 TourAPI에서 먼저 좌표를
    가져온다(get_spot_detail은 600초 캐시라 상세페이지의 다른 호출과 중복돼도 실호출은 1회).

    TourAPI의 mapy=위도, mapx=경도다. 뒤집으면 에러 없이 엉뚱한 지점의 기온이 내려온다.

    날씨 조회가 실패해도 항상 200을 반환한다(available=false). 관광지 자체가 없을 때만 404.
    """
    item = await tour_service.get_spot_detail(content_id)
    if not item:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다.")

    try:
        lat = float(item.get("mapy") or 0)
        lng = float(item.get("mapx") or 0)
    except (TypeError, ValueError):
        return unavailable_weather()

    if lat == 0 and lng == 0:
        # 좌표가 비어 있는 관광지. 0,0으로 조회하면 대서양 한가운데 기온이 내려온다.
        return unavailable_weather()

    return await weather_service.get_current_weather(lat, lng)


@router.get("/{content_id}/photos", response_model=List[PhotoItem])
async def spot_photos(content_id: str, keyword: Optional[str] = None, num_of_rows: int = 10):
    """
    관광지 사진 갤러리 조회 (PhotoGalleryService1)
    - keyword가 없으면 관광지 이름으로 자동 검색
    """
    if not keyword:
        # 관광지 이름 조회
        item = await tour_service.get_spot_detail(content_id)
        keyword = item.get("title", "") if item else ""
    
    if not keyword:
        raise HTTPException(status_code=400, detail="검색 키워드를 지정해주세요.")
    
    photos = await photo_service.get_gallery_images(keyword=keyword, num_of_rows=num_of_rows)
    return photos


@router.get("/{content_id}/crowdedness", response_model=CrowdednessInfo)
async def spot_crowdedness(content_id: str):
    """관광지 혼잡도 조회 (집중률 API + 시간 기반 fallback) — 레거시, 앱 미사용"""
    # 집중률 조회에 관광지명·주소가 필요해져서 detail을 먼저 받아야 한다(병렬 불가).
    item = await tour_service.get_spot_detail(content_id)
    if not item:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다.")

    return await crowdedness_service.estimate_crowdedness(
        content_id, item.get("title", ""), item.get("addr1")
    )


async def _collect_weather(item: dict) -> WeatherInfo:
    """좌표가 성립할 때만 날씨를 조회한다. /weather 엔드포인트와 같은 규칙이다
    (mapy=위도, mapx=경도. 뒤집으면 에러 없이 엉뚱한 지점 기온이 온다)."""
    try:
        lat = float(item.get("mapy") or 0)
        lng = float(item.get("mapx") or 0)
    except (TypeError, ValueError):
        return unavailable_weather()
    if lat == 0 and lng == 0:
        return unavailable_weather()
    return await weather_service.get_current_weather(lat, lng)


@router.get("/{content_id}/briefing", response_model=BriefingResponse)
async def spot_briefing(content_id: str, db: AsyncSession = Depends(get_db)):
    """AI 브리핑 (기능 10) — Gemini가 오늘 이 관광지의 상황을 3~4문장으로 요약한다.

    재료는 네 갈래다: 관광지 개요(TourAPI) · 현재 날씨(Open-Meteo) · 방문 집중률 **예측**
    (한국관광공사) · 당일(KST) 현장 **제보**(우리 DB). 예측과 실측은 성격이 달라 하나의
    값으로 합치지 않고 프롬프트에도 각각 별개 라벨로 넣는다(기능 9의 확정 정책). 그래서
    폐기된 CrowdednessService(둘을 섞던 레거시)는 여기서 쓰지 않는다.

    응답 계약: 관광지 자체가 없을 때(404)를 빼면 **항상 200**이다. 키 부재·무효·타임아웃·
    쿼터 소진 어느 경우에도 5xx를 내지 않고 source="TEMPLATE"로 내려간다. 예외 메시지는
    응답에 절대 싣지 않는다(예전 구현은 str(e)를 본문에 담아 화면에 노출했다).

    폴백 3단: 유효 캐시(CACHED_AI) → AI 호출(AI, 타임아웃 GEMINI_TIMEOUT_SECONDS) →
    템플릿 문장(TEMPLATE). 만료 캐시 단계는 없다 — 메모리 캐시라 만료되면 그냥 사라진다.
    """
    item = await tour_service.get_spot_detail(content_id)
    if not item:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다.")

    title = item.get("title", "")

    # 재료 수집 (1) 외부 소스. 집중률과 날씨는 서로 독립이라 병렬로 부른다. 하나가 실패해도
    # 브리핑 전체를 잃지 않도록 예외를 값으로 받아(return_exceptions) 개별적으로 흡수한다.
    congestion, weather = await asyncio.gather(
        congestion_service.get_spot_congestion(content_id, title, item.get("addr1")),
        _collect_weather(item),
        return_exceptions=True,
    )
    if isinstance(congestion, BaseException):
        congestion = None
    if isinstance(weather, BaseException):
        weather = None

    # 재료 수집 (2) 우리 DB의 당일 제보. 두 조회를 gather로 묶지 않고 순차로 돌린다 —
    # AsyncSession은 동시 사용이 안전하지 않아서 같은 세션에 두 쿼리를 겹치면
    # "another operation is in progress"로 터진다. 로컬 SQLite 조회라 순차여도 부담이 없다.
    # cutoff는 LIVE 상태창과 같은 함수를 공유한다(services/report_window.py) — 상세페이지
    # 안에서 두 블록이 서로 다른 "오늘"을 말하지 않게 하기 위함이다.
    cutoff = report_window.today_cutoff_utc()
    try:
        latest, report_count = await report_window.latest_and_count(db, content_id, cutoff)
        comments = await report_window.recent_comments(
            db, content_id, cutoff, settings.BRIEFING_COMMENT_LIMIT
        )
    except Exception:
        latest, report_count, comments = None, 0, []

    materials = BriefingMaterials(
        content_id=content_id,
        title=title,
        overview=item.get("overview"),
        weather=weather,
        congestion=congestion,
        report_crowdedness=latest.crowdedness_level if latest else None,
        report_waiting_time=latest.waiting_time if latest else None,
        report_parking_status=latest.parking_status if latest else None,
        last_report_at=latest.created_at if latest else None,
        report_count=report_count,
        comments=comments,
    )

    based_on = BriefingBasedOn(
        has_report=materials.has_report,
        has_congestion=materials.has_congestion,
        has_weather=materials.has_weather,
    )

    # Q3 — 당일 제보도 없고 집중률 예측도 없으면 "실시간 브리핑"이라 부를 근거가 없다.
    # AI를 부르면 그냥 관광 소개문이 나오는데 거기에 AI 라벨이 붙는 게 문제다. 호출을
    # 생략하고 제보를 유도한다(비용도 실제 활동이 있는 곳에만 든다).
    if materials.is_empty:
        return BriefingResponse(
            content_id=content_id,
            full_briefing=render_no_material(materials),
            source="NONE",
            generated_at=datetime.utcnow(),
            based_on=based_on,
        )

    # 1단: 유효 캐시. 키에 재료 서명이 들어가므로, 재료가 그대로일 때만 히트한다.
    cache_key = build_signature(materials)
    cached = _briefing_cache.get(cache_key)
    if cached is not None:
        text, generated_at = cached
        return BriefingResponse(
            content_id=content_id,
            full_briefing=text,
            source="CACHED_AI",
            generated_at=generated_at,
            based_on=based_on,
        )

    # 2단: AI 호출. 실패·타임아웃이면 None이 돌아온다(예외는 던지지 않는다).
    generated = await gemini_service.generate(materials)
    if generated:
        now = datetime.utcnow()
        _briefing_cache.set(
            cache_key, (generated, now), ttl_seconds=settings.BRIEFING_CACHE_TTL_SECONDS
        )
        return BriefingResponse(
            content_id=content_id,
            full_briefing=generated,
            source="AI",
            generated_at=now,
            based_on=based_on,
        )

    # 3단: 템플릿. 가진 재료만 이어 붙이고 새로운 사실을 만들지 않는다. 캐시에 담지 않는다
    # — 다음 요청에서 AI를 다시 시도해야 하기 때문이다(일시적 실패를 굳히지 않는다).
    return BriefingResponse(
        content_id=content_id,
        full_briefing=render_template(materials),
        source="TEMPLATE",
        generated_at=datetime.utcnow(),
        based_on=based_on,
    )
