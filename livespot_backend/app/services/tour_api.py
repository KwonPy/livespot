import aiohttp
import asyncio
from typing import Dict, Any, List, Optional
from app.config import settings
from app.services.http_client import get_session
from app.services.cache import TTLCache
import logging

logger = logging.getLogger(__name__)


class TourAPIService:
    """한국관광공사 국문관광정보서비스 (KorService2) 연동"""

    BASE_URL = "https://apis.data.go.kr/B551011/KorService2"

    # 서울 지역코드
    AREA_CODE_SEOUL = "1"

    # 주요 콘텐트타입
    CONTENT_TYPES = {
        "관광지": "12",
        "문화시설": "14",
        "축제공연행사": "15",
        "여행코스": "25",
        "레포츠": "28",
        "쇼핑": "38",
    }

    def __init__(self):
        self.api_key = settings.TOUR_API_KEY
        self.base_params = {
            "ServiceKey": self.api_key,
            "MobileOS": "AND",
            "MobileApp": "LiveSpot",
            "_type": "json",
        }
        self._cache = TTLCache()

    async def _fetch(self, endpoint: str, params: Dict[str, Any], max_retries: int = 3) -> Dict[str, Any]:
        url = f"{self.BASE_URL}/{endpoint}"
        full_params = {**self.base_params, **params}
        session = get_session()

        for attempt in range(max_retries + 1):
            try:
                async with session.get(url, params=full_params) as response:
                    if response.status == 200:
                        try:
                            data = await response.json(content_type=None)
                            return data
                        except Exception as e:
                            logger.error(f"JSON 파싱 실패: {e}")
                            text = await response.text()
                            logger.error(f"응답 내용: {text[:500]}")
                            return {}
                    elif response.status == 429 and attempt < max_retries:
                        wait_seconds = 2 ** attempt  # 1s, 2s, 4s
                        logger.warning(f"429 (요청 과다) - {wait_seconds}초 대기 후 재시도 ({attempt + 1}/{max_retries})")
                        await asyncio.sleep(wait_seconds)
                        continue
                    else:
                        logger.error(f"API 호출 실패: {response.status}")
                        return {}
            except (asyncio.TimeoutError, aiohttp.ClientError) as e:
                logger.error(f"TourAPI 호출 실패 ({endpoint}): {e}")
                return {}
        return {}

    def _extract_items(self, data: Dict[str, Any]) -> List[Dict]:
        """TourAPI 공통 응답에서 items 추출"""
        try:
            body = data.get("response", {}).get("body", {})
            items = body.get("items", {})
            if isinstance(items, str) and items == "":
                return []
            item_list = items.get("item", [])
            # 단건 응답 시 dict로 올 수 있음
            if isinstance(item_list, dict):
                return [item_list]
            return item_list if item_list else []
        except Exception:
            return []

    # ──────────────────── 지역기반 관광정보 조회 ────────────────────

    async def get_area_based_list(
        self,
        area_code: str = "1",
        content_type_id: Optional[str] = None,
        page: int = 1,
        num_of_rows: int = 50,
    ) -> List[Dict]:
        """areaBasedList2 - 지역 기반 관광지 목록 조회"""
        params = {
            "areaCode": area_code,
            "pageNo": page,
            "numOfRows": num_of_rows,
            "arrange": "O",  # 제목순
        }
        if content_type_id:
            params["contentTypeId"] = content_type_id

        cache_key = f"area:{area_code}:{content_type_id}:{page}:{num_of_rows}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        data = await self._fetch("areaBasedList2", params)
        items = self._extract_items(data)
        self._cache.set(cache_key, items, ttl_seconds=300)
        return items

    async def get_all_seoul_spots(self, num_of_rows: int = 50) -> List[Dict]:
        """서울 주요 관광지 전체 조회 (콘텐트타입 12, 14, 15, 25, 28) - 병렬 호출"""
        tasks = [
            self.get_area_based_list(
                area_code=self.AREA_CODE_SEOUL,
                content_type_id=type_id,
                num_of_rows=num_of_rows,
            )
            for type_id in self.CONTENT_TYPES.values()
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        all_spots = []
        for (type_name, type_id), result in zip(self.CONTENT_TYPES.items(), results):
            if isinstance(result, Exception):
                logger.error(f"[{type_name}] 조회 실패: {result}")
                continue
            all_spots.extend(result)
            logger.info(f"[{type_name}] {len(result)}건 조회")
        return all_spots

    # ──────────────────── 공통정보 조회 ────────────────────

    async def get_spot_detail(self, content_id: str) -> Dict[str, Any]:
        """detailCommon2 - 관광지 공통 상세정보 조회"""
        cache_key = f"detail:{content_id}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        params = {
            "contentId": content_id,
        }
        data = await self._fetch("detailCommon2", params)
        items = self._extract_items(data)
        result = items[0] if items else {}
        self._cache.set(cache_key, result, ttl_seconds=600)
        return result

    # ──────────────────── 소개정보 조회 ────────────────────

    async def get_spot_intro(self, content_id: str, content_type_id: str) -> Dict[str, Any]:
        """detailIntro2 - 소개정보 조회 (운영시간, 입장료 등)"""
        cache_key = f"intro:{content_id}:{content_type_id}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        params = {
            "contentId": content_id,
            "contentTypeId": content_type_id,
        }
        data = await self._fetch("detailIntro2", params)
        items = self._extract_items(data)
        result = items[0] if items else {}
        self._cache.set(cache_key, result, ttl_seconds=600)
        return result

    # ──────────────────── 키워드 검색 ────────────────────

    async def search_spots(
        self,
        keyword: str,
        area_code: Optional[str] = None,
        content_type_id: Optional[str] = None,
        page: int = 1,
    ) -> List[Dict]:
        """searchKeyword2 - 키워드 검색.

        area_code 기본값은 반드시 None이어야 한다 — TourAPI의 areaCode 필터는 그 관광지
        레코드의 areacode/sigungucode 필드가 채워져 있어야 매칭되는데, 경복궁(126508)처럼
        오래된(2003년 등록) 레코드는 이 필드가 TourAPI 쪽에서 아예 비어 있는 경우가 있다.
        예전엔 여기 기본값이 "1"(서울)이었는데, 그 때문에 정작 서울에 있는 경복궁 같은
        유명 관광지가 키워드 검색 결과에서 조용히 빠지는 버그가 있었다. 서울 한정 노출이
        필요한 화면은(예: 홈 화면 지역 목록) area_code를 명시적으로 넘기고, 이 메서드
        자체는 지역 제한 없이 검색하는 게 기본이어야 한다.
        """
        params = {
            "keyword": keyword,
            "pageNo": page,
            "numOfRows": 20,
            "arrange": "O",
        }
        if area_code:
            params["areaCode"] = area_code
        if content_type_id:
            params["contentTypeId"] = content_type_id

        data = await self._fetch("searchKeyword2", params)
        return self._extract_items(data)

    # ──────────────────── 위치기반 관광정보 조회 ────────────────────

    async def get_nearby_spots(
        self, lat: float, lng: float, radius: int = 5000, num_of_rows: int = 20
    ) -> List[Dict]:
        """locationBasedList2 - 위치 기반 주변 관광지 조회 (거리순 정렬)"""
        # 소수점 3자리(~100m)로 반올림해 근처 재조회를 캐시로 흡수
        cache_key = f"nearby:{round(lat, 3)}:{round(lng, 3)}:{radius}:{num_of_rows}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        params = {
            "mapX": lng,
            "mapY": lat,
            "radius": radius,
            "pageNo": 1,
            "numOfRows": num_of_rows,
            "arrange": "S",  # 거리순 정렬
        }
        data = await self._fetch("locationBasedList2", params)
        items = self._extract_items(data)
        self._cache.set(cache_key, items, ttl_seconds=120)
        return items
