import asyncio
from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.db.models.report import Report
from app.models.schemas import LiveStatusResponse, HotspotEntry
from app.services.tour_api import TourAPIService
from app.services.congestion import CongestionService
from app.services.report_window import (
    latest_and_count as _latest_and_count,
    live_window_cutoff_utc as _window_cutoff,
    today_cutoff_utc as _today_cutoff_utc,
)

router = APIRouter()
tour_service = TourAPIService()
congestion_service = CongestionService()

# 혼잡도 우선순위 정렬용. 공식 등급 기준이 아니라 랭킹 정렬만을 위한 내부 값.
_CROWD_SEVERITY = {"BUSY": 2, "NORMAL": 1, "EASY": 0}

# 집중률 등급(green/yellow/red) -> HotspotEntry의 통일된 display_level.
_CONGESTION_TO_LEVEL = {"red": "BUSY", "yellow": "NORMAL", "green": "EASY"}


def _clean(value) -> str | None:
    """빈 문자열을 None으로 정규화한다.

    TourAPI는 이미지가 없는 관광지의 firstimage를 빈 문자열로 준다. 그대로 내려가면
    앱의 `imageUrl != null` 분기를 통과해 깨진 이미지 자리가 생긴다
    (services/spot_lookup.py::resolve_spot_cards와 같은 이유·같은 처리)."""
    if value is None:
        return None
    text = str(value).strip()
    return text or None


# 시간창 계산(_window_cutoff / _today_cutoff_utc)과 제보 조회(_latest_and_count)는
# services/report_window.py로 옮겼다. AI 브리핑이 같은 "당일(KST)" 정의를 써야 하는데,
# 복붙해 두면 한쪽만 고쳐졌을 때 상세페이지 안에서 LIVE 상태창과 브리핑이 서로 다른
# 날짜 기준으로 말하게 된다. 동작은 이전과 동일하다.


@router.get("/status/{content_id}", response_model=LiveStatusResponse)
async def get_live_status(content_id: str, db: AsyncSession = Depends(get_db)):
    """상세페이지 LIVE 상태창용. 매번 실시간 계산한다(설계 원칙: 방금 올린 제보가 바로 보여야 함).

    is_live/recent_report_count는 "최근 LIVE_WINDOW_HOURS" 기준(활동성 판정)이고,
    현재 혼잡도/대기시간/주차는 "당일(KST)" 기준(정보 신선도)으로 서로 다른 시간창을 쓴다.
    당일 제보가 하나도 없으면 현재 상황 3개 필드는 전부 null — 어제 값을 그대로 보여주지 않는다.
    """
    latest_window, count = await _latest_and_count(db, content_id, _window_cutoff())
    latest_today, _ = await _latest_and_count(db, content_id, _today_cutoff_utc())

    return LiveStatusResponse(
        content_id=content_id,
        is_live=latest_window is not None,
        recent_report_count=count,
        current_crowdedness=latest_today.crowdedness_level if latest_today else None,
        current_waiting_time=latest_today.waiting_time if latest_today else None,
        current_parking_status=latest_today.parking_status if latest_today else None,
        last_report_at=latest_today.created_at if latest_today else None,
    )


@router.get("/hotspots", response_model=List[HotspotEntry])
async def get_hotspots(limit: int = 5, db: AsyncSession = Depends(get_db)):
    """실시간 핫스팟 TOP N (Live 페이지). 관광지별 혼잡 상태를 두 소스 중 하나로 판정한다.

    1순위: 최근 LIVE_WINDOW_HOURS 안의 실제 현장 제보. 2순위: 그런 제보가 없는 관광지는
    한국관광공사 방문 집중률 예측으로 대체한다(서울 전체 관광지 대상). 정렬은 소스를 섞지
    않는다 — 제보가 있는 관광지를 전부 먼저 나열(혼잡도 desc → 제보 최신성 desc → 제보
    건수 desc)하고, 그래도 자리가 남으면 집중률 desc로 채운다. (function.md 기능 9 원칙:
    두 데이터는 성격이 달라 하나의 값으로 섞지 않는다 — 여기서는 "섞지 않는 정렬"로 반영.)
    """
    cutoff = _window_cutoff()
    spot_ids = (
        await db.scalars(
            select(Report.spot_content_id).where(Report.created_at >= cutoff).distinct()
        )
    ).all()

    report_candidates = []
    for spot_id in spot_ids:
        latest, count = await _latest_and_count(db, spot_id, cutoff)
        if latest is None:
            continue
        report_candidates.append((spot_id, latest, count))

    # 혼잡도 desc → 최신성 desc → 건수 desc. reverse=True 하나로 세 기준 모두 내림차순이 된다.
    report_candidates.sort(
        key=lambda c: (_CROWD_SEVERITY.get(c[1].crowdedness_level, 0), c[1].created_at, c[2]),
        reverse=True,
    )
    report_spot_ids = {spot_id for spot_id, _, _ in report_candidates}
    top_report = report_candidates[:limit]

    results: List[HotspotEntry] = []

    if top_report:
        # 관광지 제목/주소는 로컬에 캐싱하지 않으므로(설계 원칙) TourAPI를 그때그때 병렬 호출해서 붙인다.
        details = await asyncio.gather(*[tour_service.get_spot_detail(spot_id) for spot_id, _, _ in top_report])
        for (spot_id, latest, count), detail in zip(top_report, details):
            if not detail:
                continue
            results.append(
                HotspotEntry(
                    content_id=spot_id,
                    spot_title=detail.get("title", ""),
                    spot_address=detail.get("addr1"),
                    spot_image_url=_clean(detail.get("firstimage")),
                    basis="REPORT",
                    display_level=latest.crowdedness_level,
                    report_count=count,
                    last_report_at=latest.created_at,
                )
            )

    remaining = limit - len(results)
    if remaining > 0:
        # 제보가 부족한 나머지 자리는 집중률 예측으로 채운다. 서울 전체 관광지가 후보군이며
        # (기존 "/spots/all"과 동일 소스), 이미 제보로 뽑힌 관광지는 중복으로 넣지 않는다.
        all_spots = await tour_service.get_all_seoul_spots(num_of_rows=30)
        seen_ids = set()
        candidates = []
        for s in all_spots:
            cid = str(s.get("contentid", ""))
            if not cid or cid in seen_ids or cid in report_spot_ids:
                continue
            seen_ids.add(cid)
            candidates.append(s)

        batch = [(str(s.get("contentid")), s.get("title", ""), s.get("addr1")) for s in candidates]
        congestion_map = await congestion_service.get_congestion_batch(batch)

        congestion_candidates = []
        for s in candidates:
            cid = str(s.get("contentid"))
            info = congestion_map.get(cid)
            if info is None or info.level == "unknown" or info.congestion_rate is None:
                continue
            congestion_candidates.append((s, info))

        congestion_candidates.sort(key=lambda c: c[1].congestion_rate, reverse=True)

        for s, info in congestion_candidates[:remaining]:
            results.append(
                HotspotEntry(
                    content_id=str(s.get("contentid")),
                    spot_title=s.get("title", ""),
                    spot_address=s.get("addr1"),
                    spot_image_url=_clean(s.get("firstimage")),
                    basis="CONGESTION",
                    display_level=_CONGESTION_TO_LEVEL.get(info.level, "EASY"),
                    congestion_rate=info.congestion_rate,
                )
            )

    return results
