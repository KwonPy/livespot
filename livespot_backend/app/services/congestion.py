import asyncio
import logging
import re
from datetime import datetime, timedelta
from typing import Any, Dict, Iterable, List, Optional, Tuple

import aiohttp

from app.config import settings
from app.models.schemas import CongestionInfo
from app.services.cache import TTLCache
from app.services.http_client import get_session
from app.services.region_codes import resolve_region_candidates

logger = logging.getLogger(__name__)

_KST_OFFSET = timedelta(hours=9)


def _today_kst_ymd() -> str:
    return (datetime.utcnow() + _KST_OFFSET).strftime("%Y%m%d")


def _seconds_until_kst_midnight() -> float:
    """집중률은 baseYmd(일 단위) 데이터라 자정을 넘기기 전까지는 값이 바뀌지 않는다.
    그래서 캐시를 당일 자정까지 유지한다 — 개발계정 일일 쿼터(1000회)를 아끼는 효과가 크다."""
    now_kst = datetime.utcnow() + _KST_OFFSET
    tomorrow = datetime(now_kst.year, now_kst.month, now_kst.day) + timedelta(days=1)
    return max((tomorrow - now_kst).total_seconds(), 60.0)


# ──────────────────── 관광지명 매칭 ────────────────────
# 집중률 API는 content_id가 없고 관광지명(tAtsNm)이 사실상 유일한 키다. TourAPI의
# title과 표기가 조금씩 달라서('덕수궁 대한문' vs '덕수궁') 단계적으로 느슨하게 맞춘다.

_PAREN_RE = re.compile(r"[(\[（【].*?[)\]）】]")


def _squash(name: str) -> str:
    return re.sub(r"\s+", "", name)


def _strip_paren(name: str) -> str:
    return _squash(_PAREN_RE.sub("", name))


def build_name_index(names: Iterable[str]) -> Dict[str, Dict[str, str]]:
    """매칭 단계별 조회표를 미리 만들어 둔다. 값은 항상 원본 tAtsNm."""
    exact: Dict[str, str] = {}
    squashed: Dict[str, str] = {}
    stripped: Dict[str, str] = {}
    for n in names:
        exact.setdefault(n, n)
        squashed.setdefault(_squash(n), n)
        stripped.setdefault(_strip_paren(n), n)
    return {"exact": exact, "squashed": squashed, "stripped": stripped}


def match_name(title: str, index: Dict[str, Dict[str, str]]) -> Optional[str]:
    """TourAPI 관광지명 -> 집중률 데이터셋의 tAtsNm. 못 찾으면 None.

    마지막 단계인 접두 매칭은 '덕수궁 대한문 -> 덕수궁'처럼 같은 관광지의 세부 지점을
    회수하기 위한 것이다. 3글자 미만 이름은 오탐이 많아 접두 매칭에서 제외하고,
    여러 개가 걸리면 가장 긴 것을 택한다.
    """
    if not title:
        return None

    if title in index["exact"]:
        return index["exact"][title]

    squashed_title = _squash(title)
    if squashed_title in index["squashed"]:
        return index["squashed"][squashed_title]

    stripped_title = _strip_paren(title)
    if stripped_title in index["stripped"]:
        return index["stripped"][stripped_title]

    best: Optional[str] = None
    for key, original in index["stripped"].items():
        if len(key) >= 3 and stripped_title.startswith(key):
            if best is None or len(key) > len(_strip_paren(best)):
                best = original
    return best


class CongestionService:
    """관광지별 집중률 추이 예측 정보 (TatsCnctrRateService) 연동.

    ⚠️ 이 API의 지역코드는 TourAPI 본체(areaCode 1~39)가 아니라 **행정표준코드**다
    (서울=11, 종로구=11110). TourAPI 코드를 넣으면 에러 없이 조용히 0건이 돌아온다.
    또 areaCd/signguCd가 둘 다 필수이며, baseYmd 같은 날짜 파라미터는 받지 않는다 —
    호출하면 오늘부터 30일치가 한 번에 오고, 우리는 그중 당일 행만 쓴다.
    tAtsNm(관광지명)은 문서상 필수로 적혀 있으나 실제로는 선택 필터라, 생략하면
    해당 시군구의 관광지 전체가 내려온다. 덕분에 마커 N개를 시군구 1회 호출로 덮는다.
    """

    BASE_URL = "https://apis.data.go.kr/B551011/TatsCnctrRateService"

    # 시군구 하나의 관광지 수 × 30일. 종로구가 113곳 × 30일 = 3390행이라 넉넉히 잡는다.
    _NUM_OF_ROWS = 5000

    def __init__(self):
        self.api_key = settings.TOUR_API_KEY
        self.base_params = {
            "ServiceKey": self.api_key,
            "MobileOS": "AND",
            "MobileApp": "LiveSpot",
            "_type": "json",
        }
        self._cache = TTLCache()

    async def _fetch(self, endpoint: str, params: Dict[str, Any]) -> Dict[str, Any]:
        url = f"{self.BASE_URL}/{endpoint}"
        full_params = {**self.base_params, **params}
        session = get_session()

        try:
            async with session.get(url, params=full_params) as response:
                if response.status == 200:
                    try:
                        return await response.json(content_type=None)
                    except Exception as e:
                        logger.error(f"집중률 API JSON 파싱 실패: {e}")
                        return {}
                logger.error(f"집중률 API 호출 실패: {response.status}")
                return {}
        except (asyncio.TimeoutError, aiohttp.ClientError) as e:
            logger.error(f"집중률 API 호출 실패: {e}")
            return {}

    def _extract_items(self, data: Dict[str, Any]) -> List[Dict]:
        try:
            body = data.get("response", {}).get("body", {})
            items = body.get("items", {})
            if isinstance(items, str):
                return []
            item_list = items.get("item", [])
            if isinstance(item_list, dict):
                return [item_list]
            return item_list or []
        except Exception:
            return []

    def _rate_to_level(self, rate: Optional[float]) -> Tuple[str, str]:
        """집중률 수치를 등급과 설명으로. 등급 용어는 '여유/보통/높음' — 현장 제보 기반
        실측 배지의 '여유/보통/혼잡'과 의도적으로 다르게 둬서, 말만 봐도 어느 쪽
        데이터인지 구분되게 한다(기능 9)."""
        if rate is None:
            return "unknown", "집중률 정보 없음"
        if rate >= 70:
            return "red", f"방문 집중 높음 (집중률 {rate:.0f}%)"
        if rate >= 40:
            return "yellow", f"방문 집중 보통 (집중률 {rate:.0f}%)"
        return "green", f"방문 집중 여유 (집중률 {rate:.0f}%)"

    # ──────────────────── 시군구 단위 조회 ────────────────────

    async def get_sigungu_rates(self, area_cd: str, signgu_cd: str) -> Dict[str, float]:
        """시군구 하나의 **당일** 집중률을 {관광지명: 집중률}로 돌려준다."""
        today = _today_kst_ymd()
        cache_key = f"rate:{area_cd}:{signgu_cd}:{today}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        data = await self._fetch(
            "tatsCnctrRatedList",
            {
                "pageNo": 1,
                "numOfRows": self._NUM_OF_ROWS,
                "areaCd": area_cd,
                "signguCd": signgu_cd,
            },
        )

        rates: Dict[str, float] = {}
        for item in self._extract_items(data):
            if str(item.get("baseYmd", "")) != today:
                continue  # 30일치가 함께 오므로 당일 행만 취한다
            name = item.get("tAtsNm")
            if not name:
                continue
            try:
                rates[str(name)] = float(item.get("cnctrRate"))
            except (TypeError, ValueError):
                continue

        # 응답이 비어 있어도(그 지역에 데이터가 없는 경우) 캐싱해 반복 호출을 막는다.
        self._cache.set(cache_key, rates, ttl_seconds=_seconds_until_kst_midnight())
        return rates

    async def _rates_for_addresses(self, addresses: Iterable[Optional[str]]) -> Dict[str, float]:
        """여러 주소에 걸친 시군구를 중복 없이 모아 한 번씩만 호출하고 합친다."""
        regions = {
            region
            for address in addresses
            for region in resolve_region_candidates(address)
        }
        if not regions:
            return {}

        results = await asyncio.gather(
            *(self.get_sigungu_rates(a, s) for a, s in regions),
            return_exceptions=True,
        )

        merged: Dict[str, float] = {}
        for r in results:
            if isinstance(r, dict):
                merged.update(r)
        return merged

    # ──────────────────── 외부에 노출되는 조회 ────────────────────

    def _build(self, content_id: Optional[str], title: str, rates: Dict[str, float]) -> CongestionInfo:
        matched = match_name(title, build_name_index(rates.keys())) if rates else None
        if matched is None:
            return CongestionInfo(
                content_id=content_id,
                level="unknown",
                description="이 관광지는 집중률 예측 대상이 아닙니다.",
            )

        rate = rates[matched]
        level, description = self._rate_to_level(rate)
        return CongestionInfo(
            content_id=content_id,
            spot_name=matched,  # 이름이 title과 다르면 앱이 "OO 기준"이라고 밝힐 수 있다
            base_ymd=_today_kst_ymd(),
            congestion_rate=rate,
            level=level,
            description=description,
        )

    async def get_spot_congestion(
        self, content_id: str, title: str, address: Optional[str]
    ) -> CongestionInfo:
        """단건 조회(상세페이지). 주소만 있으면 전국 어느 관광지든 동작한다."""
        rates = await self._rates_for_addresses([address])
        return self._build(content_id, title, rates)

    async def get_congestion_batch(
        self, spots: List[Tuple[str, str, Optional[str]]]
    ) -> Dict[str, CongestionInfo]:
        """지도용 일괄 조회. spots는 (content_id, title, address) 목록.

        화면에 보이는 관광지들의 시군구만 중복 없이 호출하므로, 보통 마커 20개에
        API 호출은 1~3회다. 관광지마다 개별 호출해도 결과는 같고 호출만 20배가 된다
        — 데이터셋에 없는 관광지는 이름을 콕 집어 물어도 없기 때문이다.
        """
        rates = await self._rates_for_addresses(address for _, _, address in spots)
        index = build_name_index(rates.keys()) if rates else None

        result: Dict[str, CongestionInfo] = {}
        for content_id, title, _ in spots:
            matched = match_name(title, index) if index else None
            if matched is None:
                result[content_id] = CongestionInfo(
                    content_id=content_id,
                    level="unknown",
                    description="이 관광지는 집중률 예측 대상이 아닙니다.",
                )
                continue
            rate = rates[matched]
            level, description = self._rate_to_level(rate)
            result[content_id] = CongestionInfo(
                content_id=content_id,
                spot_name=matched,
                base_ymd=_today_kst_ymd(),
                congestion_rate=rate,
                level=level,
                description=description,
            )
        return result
