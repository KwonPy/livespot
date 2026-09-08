import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Report(Base):
    """기능 2(현장 제보)의 스키마. spot_content_id는 로컬 FK가 아니라
    TourAPI content_id 원문 문자열 (function.md 설계 원칙 2)."""

    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    spot_content_id: Mapped[str] = mapped_column(String(20), nullable=False, index=True)

    crowdedness_level: Mapped[str] = mapped_column(String(10), nullable=False)  # EASY / NORMAL / BUSY
    waiting_time: Mapped[str] = mapped_column(String(10), nullable=False)  # NONE / UNDER_10 / 10_TO_30 / OVER_30
    parking_status: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)  # EASY / NORMAL / FULL
    comment: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    photo_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    gps_verified: Mapped[bool] = mapped_column(Boolean, nullable=False)

    # 클라이언트가 제보 창을 열 때 발급하는 고유번호. 같은 번호로 재제출되면
    # 새로 만들지 않고 기존 결과를 돌려준다 (중복 제보/중복 적립 방지).
    client_request_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow, index=True)
