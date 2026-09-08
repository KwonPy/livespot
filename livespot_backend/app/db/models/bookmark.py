import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Bookmark(Base):
    """사용자가 저장한 관광지(기능 12 "북마크").

    spot_content_id는 reports·spot_notification_settings와 동일하게 TourAPI content_id
    원문 문자열이다 (로컬 spots 테이블 없음 — 설계 원칙 2). 관광지 제목·주소·대표이미지는
    저장하지 않고 목록 조회 시점에 TourAPI에서 조인한다.

    중복 북마크는 라우터의 조건문이 아니라 UNIQUE 제약이 최종 방어선이다. 북마크는
    만료되지 않으므로 TTL·"오늘(KST)" 필터·정리 배치를 두지 않는다.
    """

    __tablename__ = "bookmarks"
    __table_args__ = (
        UniqueConstraint("user_id", "spot_content_id", name="uq_bookmark_user_spot"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    spot_content_id: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow, index=True
    )
