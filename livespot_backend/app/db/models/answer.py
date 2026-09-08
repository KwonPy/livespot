import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Answer(Base):
    """기능 7(Q&A)의 답변. GPS 현장 인증된 사용자만 작성 가능 — 답변 등록 시마다
    서버가 거리를 다시 계산해 판정한다 (기능 3과 동일 기준: 100m + 오차 50m).

    정책: 한 질문에 여러 답변(복수 답변) 허용, 수정/삭제 없음. 질문 작성자 본인은
    자신의 질문에 답변할 수 없다(questions.py에서 검증).
    """

    __tablename__ = "answers"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    question_id: Mapped[str] = mapped_column(String(36), ForeignKey("questions.id"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    content: Mapped[str] = mapped_column(String(200), nullable=False)
    gps_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow, index=True)
