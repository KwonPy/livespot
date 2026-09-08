"""content_id → 관광지 제목 조회 (MyPage 활동 목록 전용, 기능 12).

왜 별도 모듈인가: `reports`·`questions`는 spot_content_id만 저장한다(설계 원칙 2,
로컬 FK 아님). "내 제보"·"내 Q&A" 목록에 관광지 이름을 보여주려면 매번 TourAPI를
조회해야 하는데, 그 로직이 두 라우터(reports.py, questions.py)에 각각 필요해서
중복을 피하려 뺐다.
"""

from typing import Any, Dict, Optional, Set

from app.services.tour_api import TourAPIService

_tour_service = TourAPIService()


async def resolve_spot_names(content_ids: Set[str]) -> Dict[str, str]:
    """content_id 집합에 대해 관광지 제목을 조회해 매핑으로 돌려준다.

    `get_spot_detail`은 TourAPIService 내부에서 10분 TTL로 캐싱되므로, 목록을 새로고침할
    때마다 반복 호출해도 실제 TourAPI 요청은 자주 나가지 않는다. 조회 실패(삭제된
    관광지·일시 장애)한 content_id는 매핑에서 그냥 빠진다 — 호출자는 없는 키를
    "관광지 정보 없음" 같은 폴백으로 처리해야 하고, 여기서 예외를 올려 목록 전체를
    실패시키지 않는다.
    """
    names: Dict[str, str] = {}
    for content_id in content_ids:
        try:
            detail = await _tour_service.get_spot_detail(content_id)
        except Exception:
            continue
        title = detail.get("title") if detail else None
        if title:
            names[content_id] = title
    return names


async def resolve_spot_cards(content_ids: Set[str]) -> Dict[str, Dict[str, Optional[str]]]:
    """content_id 집합에 대해 목록 카드용 정보(제목·주소·대표이미지)를 조회한다.

    [resolve_spot_names]와 별도 함수인 이유: 북마크 목록 카드는 제목 외에 주소와
    대표이미지까지 그리는데, 기존 함수의 반환형(Dict[str, str])을 바꾸면 이미 그것을
    쓰고 있는 reports.py·questions.py가 함께 깨진다. 내부의 `get_spot_detail`은
    TourAPIService에서 10분 TTL로 캐싱되므로 두 함수가 캐시를 공유한다 — 추가 API
    비용은 사실상 없다.

    반환값의 각 항목은 {"title", "address", "image_url"} 3키를 가지며, TourAPI 원본 키
    매핑은 `api/spots.py::parse_spot_detail`과 동일하다(addr1→address, firstimage→
    image_url). 빈 문자열은 None으로 정규화한다 — 앱이 `imageUrl != null`로 분기하는데
    빈 문자열이 올라가면 깨진 이미지 자리가 생긴다.

    조회 실패(삭제된 관광지·일시 장애)한 content_id는 매핑에서 그냥 빠진다. 여기서
    예외를 올려 목록 전체를 실패시키지 않는다 — 호출자가 폴백으로 처리한다.
    """

    def _clean(value: Any) -> Optional[str]:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    cards: Dict[str, Dict[str, Optional[str]]] = {}
    for content_id in content_ids:
        try:
            detail = await _tour_service.get_spot_detail(content_id)
        except Exception:
            continue
        if not detail:
            continue
        title = _clean(detail.get("title"))
        if not title:
            # 제목조차 없으면 카드로서 의미가 없다 — 없는 키로 두고 폴백에 맡긴다.
            continue
        cards[content_id] = {
            "title": title,
            "address": _clean(detail.get("addr1")),
            "image_url": _clean(detail.get("firstimage")),
        }
    return cards
