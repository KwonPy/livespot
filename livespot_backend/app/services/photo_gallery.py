import aiohttp
import asyncio
from typing import Dict, Any, List, Optional
from app.config import settings
from app.models.schemas import PhotoItem
from app.services.http_client import get_session
import logging

logger = logging.getLogger(__name__)


class PhotoGalleryService:
    """관광사진 정보 서비스 (PhotoGalleryService1) 연동"""

    BASE_URL = "https://apis.data.go.kr/B551011/PhotoGalleryService1"

    def __init__(self):
        self.api_key = settings.TOUR_API_KEY
        self.base_params = {
            "ServiceKey": self.api_key,
            "MobileOS": "AND",
            "MobileApp": "LiveSpot",
            "_type": "json",
        }

    async def _fetch(self, endpoint: str, params: Dict[str, Any]) -> Dict[str, Any]:
        url = f"{self.BASE_URL}/{endpoint}"
        full_params = {**self.base_params, **params}
        session = get_session()

        try:
            async with session.get(url, params=full_params) as response:
                if response.status == 200:
                    try:
                        data = await response.json(content_type=None)
                        return data
                    except Exception as e:
                        logger.error(f"사진 갤러리 API JSON 파싱 실패: {e}")
                        return {}
                else:
                    logger.error(f"사진 갤러리 API 호출 실패: {response.status}")
                    return {}
        except (asyncio.TimeoutError, aiohttp.ClientError) as e:
            logger.error(f"사진 갤러리 API 호출 실패: {e}")
            return {}

    def _extract_items(self, data: Dict[str, Any]) -> List[Dict]:
        try:
            body = data.get("response", {}).get("body", {})
            items = body.get("items", {})
            if isinstance(items, str) and items == "":
                return []
            item_list = items.get("item", [])
            if isinstance(item_list, dict):
                return [item_list]
            return item_list if item_list else []
        except Exception:
            return []

    async def get_gallery_images(
        self,
        keyword: str,
        num_of_rows: int = 10,
        page: int = 1,
    ) -> List[PhotoItem]:
        """
        galleryList1 - 관광사진 갤러리 목록 조회
        
        Args:
            keyword: 검색 키워드 (관광지 이름)
            num_of_rows: 조회 건수
        """
        params = {
            "keyword": keyword,
            "pageNo": page,
            "numOfRows": num_of_rows,
            "arrange": "A",  # 제목순
        }

        data = await self._fetch("galleryList1", params)
        items = self._extract_items(data)

        results = []
        for item in items:
            photo = PhotoItem(
                gallery_url=item.get("galWebImageUrl", item.get("galPhotographyLocation", None)),
                photo_title=item.get("galTitle", None),
                photographer=item.get("galPhotographer", None),
                search_keyword=item.get("galSearchKeyword", keyword),
            )
            results.append(photo)

        return results

    async def get_representative_image(self, spot_name: str) -> Optional[str]:
        """관광지 이름으로 대표 이미지 URL 1개 반환"""
        photos = await self.get_gallery_images(keyword=spot_name, num_of_rows=1)
        if photos and photos[0].gallery_url:
            return photos[0].gallery_url
        return None
