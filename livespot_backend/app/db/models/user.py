import uuid
from datetime import datetime

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class User(Base):
    """기능 1(로그인)의 스키마. 실제 카카오/Firebase 인증이 붙기 전까지는
    test_user 한 줄짜리 mock 데이터로만 채워진다 (function.md 구현 순서 참고)."""

    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    firebase_uid: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    nickname: Mapped[str] = mapped_column(String(50), nullable=False)
    credit_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    trust_level: Mapped[str] = mapped_column(String(20), nullable=False, default="NEWCOMER")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
