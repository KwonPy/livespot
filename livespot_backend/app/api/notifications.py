from fastapi import APIRouter, Depends
from typing import List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.db.models.notification_setting import NotificationSetting
from app.api.deps import get_current_user_id
from app.models.schemas import NotificationSettingUpsert, NotificationSettingResponse

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
