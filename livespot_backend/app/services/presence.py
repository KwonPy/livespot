"""현장 사용자(presence) 기록·집계를 한 곳에 모은 모듈 (기능 6).

이 모듈이 존재하는 이유는 재사용이다. "현장 사용자인가"의 판정은 두 곳에서 필요하다:

1. 지금: LIVE 상태창의 `onsite_user_count` (`api/live.py`)
2. 앞으로: 기능 8의 푸시 대상 명단 — "이 관광지에 최근 30분 안에 있던 사람들에게 질문 알림"

두 곳이 각자 쿼리를 짜면 "화면에는 3명이라고 떠 있는데 알림은 1명에게만 가는" 상태가
생긴다. 그래서 판정 함수를 여기 하나로 두고, 기능 8은 `get_onsite_user_ids()`를 그대로
호출하면 되게 했다. 판정 기준은 오직 `last_seen >= now() - PRESENCE_WINDOW_MINUTES`이며
앱의 현재 연결 여부·세션 상태는 참조하지 않는다 — 앱이 꺼져 있어도 30분 안이면 현장
사용자다(사용자 확정 정책).

시간창 계산 자체는 services/report_window.py가 갖고 있다(cutoff를 복붙하지 않는다).
"""

from typing import List

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.presence import Presence
from app.services.report_window import (
    presence_retention_cutoff_utc,
    presence_window_cutoff_utc,
)
from datetime import datetime


async def purge_expired_presence(db: AsyncSession) -> int:
    """마지막 신호로부터 24시간이 지난 행을 실제로 DELETE한다.

    스케줄러를 새로 도입하지 않고 위치 신호가 들어올 때 곁다리로 부른다(이 프로젝트에는
    배치 인프라가 하나도 없고, 배치가 죽으면 삭제 약속도 조용히 깨진다). 대가는 신호가
    전혀 없는 조용한 시간대에 정리가 다음 신호까지 지연되는 것 — 삭제 자체가 누락되지는 않는다.

    commit은 호출자가 한다(신호 기록과 같은 트랜잭션에 묶기 위함).
    """
    result = await db.execute(
        delete(Presence).where(Presence.last_seen < presence_retention_cutoff_utc())
    )
    return result.rowcount or 0


async def touch_presence(
    db: AsyncSession,
    *,
    user_id: str,
    spot_content_id: str,
    distance_m: float,
) -> Presence:
    """(user_id, spot_content_id) 1행을 UPSERT하고 last_seen을 현재로 갱신한다.

    방문 이력을 append하지 않는 것이 핵심이다 — 행이 하나뿐이라 이동 경로가 애초에
    복원 불가능하다. 좌표는 받지 않는다(호출자가 이미 거리로 환산해서 넘긴다).

    ON CONFLICT 구문은 방언마다 달라(SQLite/Postgres 양쪽에서 도는 마이그레이션·코드가
    필요하다) SELECT → UPDATE / INSERT 방식으로 쓰고, 동시 요청이 겹쳤을 때만
    IntegrityError를 잡아 UPDATE로 되돌린다.

    commit은 호출자가 한다.
    """
    now = datetime.utcnow()
    existing = await db.scalar(
        select(Presence).where(
            Presence.user_id == user_id,
            Presence.spot_content_id == spot_content_id,
        )
    )
    if existing is not None:
        existing.last_seen = now
        existing.distance_m = distance_m
        return existing

    row = Presence(
        user_id=user_id,
        spot_content_id=spot_content_id,
        last_seen=now,
        distance_m=distance_m,
    )
    db.add(row)
    try:
        await db.flush()
    except IntegrityError:
        # 같은 사용자의 신호 두 개가 동시에 들어온 경우. UNIQUE 제약이 최종 방어선이고,
        # 여기서는 방금 다른 요청이 만든 행을 갱신하는 쪽으로 합류한다.
        await db.rollback()
        existing = await db.scalar(
            select(Presence).where(
                Presence.user_id == user_id,
                Presence.spot_content_id == spot_content_id,
            )
        )
        if existing is None:
            raise
        existing.last_seen = now
        existing.distance_m = distance_m
        return existing
    return row


async def record_presence(
    db: AsyncSession,
    *,
    user_id: str,
    spot_content_id: str,
    distance_m: float,
) -> Presence:
    """위치 신호 1건 처리: 24시간 지난 행 파기 + 내 행 UPSERT를 한 트랜잭션으로 커밋한다.

    파기를 먼저 하는 이유는 순서가 아니라 "신호가 들어올 때마다 반드시 함께 돈다"는
    보장을 한 함수 안에 묶기 위함이다. 호출자(reports.verify_location)는 이 함수만
    부르면 되고, 정리를 잊을 방법이 없다.
    """
    await purge_expired_presence(db)
    row = await touch_presence(
        db, user_id=user_id, spot_content_id=spot_content_id, distance_m=distance_m
    )
    await db.commit()
    return row


async def count_onsite_users(db: AsyncSession, spot_content_id: str) -> int:
    """해당 관광지의 현장 사용자 수 (최근 PRESENCE_WINDOW_MINUTES분).

    사용자 단위 중복 제거다 — 같은 사람이 30분 안에 신호를 5번 보내도 1명. 테이블이
    이미 (user_id, spot_content_id) UNIQUE라 행 수와 같지만, "인원은 사용자 단위"라는
    규칙을 쿼리에도 남겨 둔다(스키마가 바뀌어도 의미가 유지되도록).

    우리 DB 조회라 실패하면 예외를 던진다 — `available:false` 폴백을 쓰지 않는다.
    그 패턴은 외부 API(날씨·집중률)용이고, 여기서 0을 대신 내려보내면 "아무도 없음"과
    "못 셌음"이 구분되지 않는다.
    """
    count = await db.scalar(
        select(func.count(func.distinct(Presence.user_id))).where(
            Presence.spot_content_id == spot_content_id,
            Presence.last_seen >= presence_window_cutoff_utc(),
        )
    )
    return count or 0


async def get_onsite_user_ids(db: AsyncSession, spot_content_id: str) -> List[str]:
    """해당 관광지의 현장 사용자 id 목록 (최근 PRESENCE_WINDOW_MINUTES분).

    기능 8(질문 알림)의 대상 명단이 될 함수다. count_onsite_users와 **같은 cutoff**를
    쓰므로 화면의 숫자와 알림 대상이 어긋나지 않는다. 지금은 아무도 호출하지 않지만,
    판정 로직을 두 번 짜지 않기 위해 인원 집계와 함께 만들어 둔다(사용자 확정 정책 Q4).
    """
    rows = await db.scalars(
        select(Presence.user_id)
        .where(
            Presence.spot_content_id == spot_content_id,
            Presence.last_seen >= presence_window_cutoff_utc(),
        )
        .distinct()
    )
    return list(rows.all())
