import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class NotificationSetting(Base):
    """관광지별 자동 제보 유도 알림 on/off. spot_content_id는 reports와 동일하게
    TourAPI content_id 원문 문자열 (로컬 spots 테이블 없음)."""

    __tablename__ = "spot_notification_settings"
    __table_args__ = (
        UniqueConstraint("user_id", "spot_content_id", name="uq_notification_setting_user_spot"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    spot_content_id: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    push_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow
    )
