import uuid
from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Presence(Base):
    """현장 사용자 신호(기능 6). "누가 · 어느 관광지 근처에 · 마지막으로 언제 있었는지" 한 줄.

    스키마가 곧 프라이버시 정책이다:

    - **좌표를 저장하지 않는다.** 위치 신호 요청의 lat/lng는 반경 판정에만 쓰고 버리며,
      관광지로부터의 거리(distance_m)만 남긴다. 거리 하나로는 이동 경로를 복원할 수 없다.
    - **방문 이력을 쌓지 않는다.** UNIQUE(user_id, spot_content_id) 1행을 last_seen으로
      덮어쓰는 UPSERT다(bookmarks의 UNIQUE 패턴과 동일). append 방식이면 3분 주기 신호가
      1인당 하루 480행의 동선 기록이 되므로 구조적으로 막았다.
    - **24시간이 지난 행은 실제로 DELETE**한다(조회에서 감추는 것이 아니라). 스케줄러를
      새로 도입하지 않고, 위치 신호가 들어올 때마다 같은 트랜잭션에서 정리한다
      (services/presence.py::purge_expired_presence).

    "현장 인원"은 상태 컬럼이 아니라 조회 시점 계산이다 — last_seen >= now() - 30분.
    앱의 현재 연결 여부·세션 상태는 전혀 참조하지 않으므로, 앱이 완전히 종료돼 있어도
    마지막 신호가 30분 안이면 현장 사용자로 집계된다(Q&A TTL·하루 리셋과 같은 방식).

    spot_content_id는 reports·bookmarks와 동일하게 TourAPI content_id 원문 문자열이다
    (로컬 spots 테이블 없음 — 설계 원칙 2). FK가 아니다.
    """

    __tablename__ = "presences"
    __table_args__ = (
        UniqueConstraint("user_id", "spot_content_id", name="uq_presence_user_spot"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    spot_content_id: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    # 마지막 위치 신호 시각(naive UTC). 30분 창 판정과 24시간 파기 판정이 모두 이 값 하나를 본다.
    last_seen: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow, index=True
    )
    # 신호 당시 관광지까지의 거리(m). 좌표 원본 대신 남기는 유일한 위치 정보다.
    distance_m: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
