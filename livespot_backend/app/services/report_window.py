"""제보(reports) 조회의 시간창 규칙을 한 곳에 모은 모듈.

왜 별도 모듈인가: LIVE 상태창(`api/live.py`)과 AI 브리핑(`api/spots.py`)이 **똑같은
"당일" 정의**를 써야 하기 때문이다. 두 화면이 상세페이지에 나란히 그려지는데 각자
다른 기준으로 "오늘의 제보"를 판정하면, 브리핑 문장이 바로 위 LIVE 상태창과 모순된다.
과거에 이런 종류의 경계면 버그가 반복돼서, cutoff 계산을 복붙하지 않고 여기서 공유한다.

시간 규약: DB의 created_at은 naive UTC다(프로젝트 전역 규약). "당일"은 한국 여행자
서비스이므로 KST(UTC+9) 자정 기준 달력일로 판정하고, 비교를 위해 다시 naive UTC로
환산한다.
"""

from datetime import datetime, timedelta
from typing import List, Optional, Sequence, Tuple

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.models.report import Report

KST_OFFSET = timedelta(hours=9)


def today_cutoff_utc() -> datetime:
    """오늘(KST) 자정에 해당하는 naive UTC 시각.

    혼잡도/대기시간/주차처럼 신선도가 중요한 정보는 이 시각 이후의 제보만 재료로 쓴다.
    어제 값을 오늘 화면에 그대로 얹지 않기 위함이다.
    """
    now_kst = datetime.utcnow() + KST_OFFSET
    start_of_today_kst = datetime(now_kst.year, now_kst.month, now_kst.day)
    return start_of_today_kst - KST_OFFSET


def live_window_cutoff_utc() -> datetime:
    """"지금 붐빈다"(활동성)를 판정하는 최근 N시간 시간창의 시작 시각."""
    return datetime.utcnow() - timedelta(hours=settings.LIVE_WINDOW_HOURS)


def presence_window_cutoff_utc() -> datetime:
    """"현장 사용자"(기능 6)를 판정하는 최근 N분 시간창의 시작 시각.

    presences.last_seen이 이 시각 이상이면 현장 사용자다. 상태 컬럼도 배치도 쓰지 않고
    조회 시점에 계산한다. 이 cutoff는 (a) LIVE 상태창의 onsite_user_count와
    (b) 앞으로 붙을 기능 8의 알림 대상 판정이 **같은 함수**를 공유해야 하므로 여기 둔다 —
    복붙하면 "화면에는 잡히는데 알림은 안 가는" 모순이 생긴다.

    제보 모듈에 presence cutoff가 있는 게 어색해 보이지만, 이 파일의 존재 이유가
    "시간창 정의를 한 곳에 모은다"이므로 새 모듈을 파지 않고 여기에 이어 붙인다.
    """
    return datetime.utcnow() - timedelta(minutes=settings.PRESENCE_WINDOW_MINUTES)


def presence_retention_cutoff_utc() -> datetime:
    """presences 행을 실제로 DELETE하는 기준 시각. 이보다 오래된 last_seen은 파기 대상.

    30분 창(위)이 "지금 현장에 있나"의 판정이라면, 이쪽은 프라이버시 약속("24시간 뒤
    삭제")의 이행 기준이다. 두 값이 다른 목적을 가지므로 상수도 따로 둔다.
    """
    return datetime.utcnow() - timedelta(hours=settings.PRESENCE_RETENTION_HOURS)


async def latest_and_count(
    db: AsyncSession, spot_content_id: str, cutoff: datetime
) -> Tuple[Optional[Report], int]:
    """cutoff 이후 제보 중 가장 최근 1건과 총 건수."""
    latest = await db.scalar(
        select(Report)
        .where(Report.spot_content_id == spot_content_id, Report.created_at >= cutoff)
        .order_by(Report.created_at.desc())
        .limit(1)
    )
    count = await db.scalar(
        select(func.count(Report.id)).where(
            Report.spot_content_id == spot_content_id, Report.created_at >= cutoff
        )
    )
    return latest, count or 0


async def recent_reports(
    db: AsyncSession, spot_content_id: str, cutoff: datetime, limit: int
) -> Sequence[Report]:
    """cutoff 이후 제보를 최신순으로 최대 limit건.

    브리핑이 "최근 3건의 코멘트"를 재료로 쓰기 위해 필요하다. latest_and_count는 1건만
    돌려주므로 그것만으로는 부족하고, 그렇다고 cutoff 계산을 따로 하면 두 화면의 "당일"이
    갈라진다 — 그래서 조회 함수만 늘리고 cutoff는 위 함수를 공유한다.
    """
    rows = await db.scalars(
        select(Report)
        .where(Report.spot_content_id == spot_content_id, Report.created_at >= cutoff)
        .order_by(Report.created_at.desc())
        .limit(limit)
    )
    return rows.all()


async def recent_comments(
    db: AsyncSession, spot_content_id: str, cutoff: datetime, limit: int
) -> List[str]:
    """cutoff 이후 제보 중 코멘트가 실제로 적힌 것만 최신순으로 최대 limit건.

    코멘트는 선택 입력이라 대부분 비어 있다. 빈 값을 세어 limit을 채우면 "최근 3건"이라
    말해놓고 실제로는 1건만 넣게 되므로, 코멘트가 있는 제보만 골라 limit을 채운다.
    """
    rows = await db.scalars(
        select(Report)
        .where(
            Report.spot_content_id == spot_content_id,
            Report.created_at >= cutoff,
            Report.comment.isnot(None),
            Report.comment != "",
        )
        .order_by(Report.created_at.desc())
        .limit(limit)
    )
    return [r.comment.strip() for r in rows.all() if r.comment and r.comment.strip()]
