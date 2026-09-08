import uuid
from datetime import datetime, timedelta

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# 질문 TTL(정책): 등록 즉시 ACTIVE, 2시간 지나면 EXPIRED. 배치 없이 조회 시점에
# created_at 기준으로 매번 계산한다 (별도 상태 컬럼/스케줄러 불필요).
QUESTION_TTL_HOURS = 2


class Question(Base):
    """기능 7(Q&A)의 질문. spot_content_id는 reports와 동일하게 TourAPI content_id 원문
    문자열 (function.md 설계 원칙 2). 자유 텍스트만 지원 — 카테고리 없음 (정책).

    상세페이지에서만 작성 가능(위치 제한 없음 — 질문자는 원래 멀리 있는 사람).
    """

    __tablename__ = "questions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    spot_content_id: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    content: Mapped[str] = mapped_column(String(200), nullable=False)

    # 답변 개수를 답변 등록 시 함께 갱신해 캐싱한다 — "답변 대기 질문"을 매번 전체
    # 집계하지 않기 위함 (function.md 기능 7 핵심 판단).
    answer_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow, index=True)

    @property
    def is_expired(self) -> bool:
        return datetime.utcnow() >= self.created_at + timedelta(hours=QUESTION_TTL_HOURS)
