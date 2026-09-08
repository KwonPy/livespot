import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class CreditLedger(Base):
    """기능 4(Credit)의 통장식 원장.

    왜 잔액 숫자 하나가 아니라 원장인가: "왜 크레딧이 줄었죠?"에 답할 수 있어야 하기
    때문이다(function.md 기능 4). 회수도 행 삭제가 아니라 음수 amount 행 1건으로 남긴다.
    users.credit_balance는 빠른 조회용 캐시일 뿐이고, 진실은 언제나 이 표의 합계다.

    spot_content_id는 reports와 동일하게 TourAPI content_id 원문 문자열이다(로컬 FK 아님).
    일일 상한("같은 장소 하루 3건")을 판정하려면 적립 시점의 장소를 원장이 알아야 하는데,
    reports를 되짚는 조인으로 풀면 답변 적립 행(장소가 질문에 딸려 있다)과 경로가 갈린다.
    """

    __tablename__ = "credit_ledger"
    __table_args__ = (
        # 이중 지급 방지의 최종 방어선(P13②). 제보는 client_request_id가 1차로 막지만
        # 답변에는 멱등 장치가 없어서, "질문당 1회"(source_id=question_id) 정책이 이
        # 제약 하나로 강제된다 — 런타임 조회 없이 DB가 거절한다.
        UniqueConstraint("user_id", "source_type", "source_id", name="uq_credit_ledger_user_source"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)

    # 음수 허용 (회수). 적립액 자체는 config.py의 상수에서 온다.
    amount: Mapped[int] = mapped_column(Integer, nullable=False)

    reason: Mapped[str] = mapped_column(String(20), nullable=False)  # REPORT / ANSWER
    source_type: Mapped[str] = mapped_column(String(20), nullable=False)  # report / answer
    # 제보 적립은 report.id, 답변 적립은 question.id (질문당 1회 정책, P14)
    source_id: Mapped[str] = mapped_column(String(36), nullable=False)

    # 일일 상한 판정용. 적립 대상이 장소와 무관해질 경우를 위해 nullable로 둔다.
    spot_content_id: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow, index=True)
