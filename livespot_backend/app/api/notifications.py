"""알림 라우터. **성격이 다른 두 기능이 한 prefix(/notifications)를 공유한다.**

1. `/settings*` — 기능 3의 **관광지별** 자동 제보 유도 알림 on/off (기본 꺼짐).
2. 그 외 — 기능 8의 **질문/답변 알림**: 목록·읽음 처리·WS 깨우기.

둘을 합치지 않은 이유: 한 스위치를 공유하면 "근접 제보 알림만 끄고 싶은데 답변 알림도
같이 꺼지는" 상태가 된다. 새 prefix를 파지 않은 이유는 엔드포인트 하나가 늘면
라우터·스키마·Dart·QA가 전부 따라 늘기 때문이다.

**2026-09-13(015)**: 기능 8 쪽에 있던 전역 스위치 `GET/POST /push-settings`가 제거됐다.
기능 8 알림은 이제 설정 없이 항상 간다. 종류는 `NEW_QUESTION`·`NEW_ANSWER` 2종 그대로다
(같은 날 1종으로 줄였다가 되돌렸다 — 015 2-2절). 여기 남아 있는 `/settings*`는
**기능 3의 다른 기능**이므로 혼동하지 말 것 — 그건 그대로 살아 있다.
"""

from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.db.seed import TEST_USER_ID
from app.db.models.notification import Notification
from app.db.models.notification_setting import NotificationSetting
from app.api.deps import get_current_user_id
from app.models.schemas import (
    NotificationEntry,
    NotificationListResponse,
    NotificationReadResponse,
    NotificationSettingUpsert,
    NotificationSettingResponse,
)
from app.services import notification as notification_service
from app.services.spot_lookup import resolve_spot_names
from app.services.ws_manager import manager as ws_manager

router = APIRouter()


@router.get("/settings", response_model=List[NotificationSettingResponse])
async def list_settings(
    enabled_only: bool = False,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """앱 실행 시 주변 관광지와 대조하기 위해 호출. enabled_only=true면
    push_enabled=True인 관광지만 돌려준다 (자동 제보 유도 알림 대상)."""
    stmt = select(NotificationSetting).where(NotificationSetting.user_id == user_id)
    if enabled_only:
        stmt = stmt.where(NotificationSetting.push_enabled.is_(True))
    rows = (await db.scalars(stmt)).all()
    return [
        NotificationSettingResponse(content_id=r.spot_content_id, push_enabled=r.push_enabled)
        for r in rows
    ]


@router.get("/settings/{content_id}", response_model=NotificationSettingResponse)
async def get_setting(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.scalar(
        select(NotificationSetting).where(
            NotificationSetting.user_id == user_id,
            NotificationSetting.spot_content_id == content_id,
        )
    )
    return NotificationSettingResponse(
        content_id=content_id,
        push_enabled=row.push_enabled if row else False,
    )


@router.post("/settings", response_model=NotificationSettingResponse)
async def upsert_setting(
    payload: NotificationSettingUpsert,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.scalar(
        select(NotificationSetting).where(
            NotificationSetting.user_id == user_id,
            NotificationSetting.spot_content_id == payload.content_id,
        )
    )
    if row is None:
        row = NotificationSetting(
            user_id=user_id,
            spot_content_id=payload.content_id,
            push_enabled=payload.push_enabled,
        )
        db.add(row)
    else:
        row.push_enabled = payload.push_enabled

    await db.commit()
    return NotificationSettingResponse(content_id=payload.content_id, push_enabled=payload.push_enabled)


# ──────────────────── 기능 8: 질문/답변 알림 ────────────────────
# 아래 엔드포인트는 위의 관광지별 설정과 무관하다. 전역 스위치는 없다 — 항상 대상이다.
#
# 주의: `/read-all`은 `/{notification_id}/read`보다 **먼저** 선언한다. FastAPI는 선언
# 순서대로 매칭하므로, 경로 파라미터 라우트가 앞에 오면 고정 경로를 삼킨다.


@router.websocket("/ws")
async def notifications_ws(websocket: WebSocket, test_user_id: Optional[str] = Query(default=None)):
    """알림 실시간 깨우기 채널(2026-09-12). **알림 데이터를 실어 보내지 않는다** — 연결이 살아
    있는 동안 새 알림이 생기면 빈 신호 하나만 받고, 클라이언트는 그 신호를 받으면 기존
    `GET /api/notifications`를 즉시 다시 부른다. 그래서 이 엔드포인트에는 인증된 조회 로직이
    없다 — 아무것도 조회하지 않기 때문이다.

    `get_current_user_id`(헤더 기반)를 그대로 쓸 수 없다: 브라우저의 WebSocket API는 핸드셰이크에
    커스텀 헤더를 실어 보낼 수 없다(`X-Test-User-Id` 불가). 그래서 같은 판정을 쿼리 파라미터로
    반복한다 — TEST_MODE가 꺼져 있으면 test_user_id를 받아도 무시하고 항상 TEST_USER_ID다.
    실제 로그인(기능 1) 전까지는 이 구분에 보안적 의미가 없다 — 폴링 엔드포인트와 동일한 수준이다.

    연결 수립 실패(끊긴 클라이언트 등)는 여기서 처리하고 상위로 올리지 않는다 — 이 채널이
    죽어도 폴백 폴링이 있으므로 알림 자체가 끊기지 않는다(P23와 같은 이유로, 이 연결의 존재
    유무가 "지금 접속 중"의 판정에 영향을 주지 않는다 — 그 판정은 여전히 폴링이 한다).
    """
    user_id = TEST_USER_ID
    if settings.TEST_MODE and test_user_id:
        user_id = test_user_id
    await ws_manager.connect(user_id, websocket)
    try:
        while True:
            # 클라이언트는 아무것도 보내지 않는다 — 연결이 끊겼는지만 감지하면 된다.
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        ws_manager.disconnect(user_id, websocket)


# `GET/POST /push-settings`(기능 8 전역 알림 스위치)는 **2026-09-13에 제거됐다**(015 N1·N2).
# 토글 UI가 사라졌고 "명시적으로 끈 사용자"라는 상태 자체가 없어졌다 — 알림은 항상 간다.
# 뒷받침하던 `user_notification_settings` 테이블도 마이그레이션 `b7f3c1e9a204`로 드롭됐다.
# 되살리려면 엔드포인트만 복원해서는 안 되고 테이블·모델·서비스 함수가 같이 와야 한다.


@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    limit: Optional[int] = Query(default=None, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """내 알림 목록(기능 8). 앱이 주기적으로 폴링하는 **경량** 엔드포인트다.

    `POST /reports/verify-location`에 얹지 않고 따로 판 이유: 그쪽은 호출마다 TourAPI 상세
    조회를 하므로, 폴링을 얹으면 TourAPI 호출량이 폴링 주기만큼 함께 는다.

    **연결된 질문이 유효한 동안(2시간)만 보인다**(P24). 알림 자신에게는 수명이 없다 —
    상태 컬럼도 배치도 없이, 조회할 때 questions와 JOIN해서 질문의 `created_at`을 비교할
    뿐이라 행은 DB에 그대로 남는다. 그래서 `expires_at`은 알림이 아니라 **질문의**
    created_at + 2시간이고, `list_active`가 JOIN 한 번으로 그 값까지 함께 가져온다
    (알림마다 질문을 다시 조회하면 N+1이 된다).

    우리 DB 조회라 실패하면 500이다 — 빈 배열 폴백을 쓰지 않는다(P11). "알림이 없음"과
    "못 읽었음"이 구분되지 않으면 앱이 조용히 빈 화면을 그린다. 다만 관광지 이름(spot_name)
    조회만은 외부 API(TourAPI)라, 실패해도 목록 전체를 실패시키지 않고 null로 둔다.
    """
    rows = await notification_service.list_active(
        db, user_id, limit=limit or settings.NOTIFICATION_LIST_LIMIT
    )
    names = await resolve_spot_names({row.spot_content_id for row, _ in rows})
    return NotificationListResponse(
        items=[
            NotificationEntry(
                id=row.id,
                type=row.type,
                spot_content_id=row.spot_content_id,
                spot_name=names.get(row.spot_content_id),
                question_id=row.question_id,
                body=row.body,
                created_at=row.created_at,
                expires_at=notification_service.expires_at_of(question_created_at),
                read_at=row.read_at,
                is_read=row.read_at is not None,
            )
            for row, question_created_at in rows
        ],
        unread_count=await notification_service.count_unread(db, user_id),
    )


@router.post("/read-all", response_model=NotificationReadResponse)
async def read_all_notifications(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """미읽음 알림을 한 번에 읽음 처리한다. 목록 화면에 들어왔을 때 호출하는 용도.

    **목록에 실제로 보이는 것만**(= 연결된 질문이 아직 2시간 안인 것만) 건드린다 —
    목록 조회와 같은 `active_join` 판정을 공유한다. 이미 사라진 알림에 read_at을 찍어봐야
    보이는 변화가 없고, 그 행은 기록으로만 남는 편이 정직하다.
    """
    rows = await notification_service.list_unread_for_update(db, user_id)
    now = datetime.utcnow()
    updated = 0
    for row in rows:
        row.read_at = now
        updated += 1
    await db.commit()
    return NotificationReadResponse(
        updated_count=updated,
        unread_count=await notification_service.count_unread(db, user_id),
    )


@router.post("/{notification_id}/read", response_model=NotificationReadResponse)
async def read_notification(
    notification_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """알림 1건 읽음 처리. 앱이 알림을 탭해 질문으로 이동할 때 함께 호출한다.

    멱등이다 — 이미 읽은 알림이면 409가 아니라 200 + updated_count=0을 돌려준다.
    다른 사람의 알림 id를 넣으면 403이 아니라 **404**다. 403은 "그 id가 존재한다"는
    사실을 알려주므로, 남의 알림 존재 여부를 캐낼 수 있게 된다.
    """
    row = await db.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없습니다")

    updated = 0
    if row.read_at is None:
        row.read_at = datetime.utcnow()
        updated = 1
        await db.commit()

    return NotificationReadResponse(
        updated_count=updated,
        unread_count=await notification_service.count_unread(db, user_id),
    )
