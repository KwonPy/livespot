import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# 알림 종류(기능 8). 컬럼에 문자열로 저장한다 — DB 방언별 ENUM 타입을 만들면 종류를
# 하나 늘릴 때마다 SQLite/Postgres 양쪽 마이그레이션이 갈린다(배포는 Postgres, 로컬은 SQLite).
TYPE_NEW_QUESTION = "NEW_QUESTION"  # 내가 최근 30분 안에 GPS 인증한 관광지에 새 질문이 올라옴
TYPE_NEW_ANSWER = "NEW_ANSWER"      # 내가 올린 질문에 답변이 달림


class Notification(Base):
    """질문/답변 알림 1건(기능 8). "누가 · 어떤 종류의 알림을 · 언제 받았고 · 읽었는가".

    설계 규칙:

    - **만료는 상태 컬럼이 아니라 조회 시점 계산이다.** 다만 기준이 **알림 자신이 아니라
      연결된 질문**이다(P24, 2026-09-10 방향 수정): `question_id`가 가리키는 질문의
      `created_at + QUESTION_TTL_HOURS(2)`가 지나면 목록에서 빠진다. 알림 전용 TTL
      (`NOTIFICATION_TTL_MINUTES=30`)은 폐기됐다 — "질문은 아직 살아 있는데 알림만 먼저
      사라져 답변하러 갈 길이 끊기는" 상태를 없애기 위함이다.
    - **읽음(`read_at`)과 유효시간은 별개로 관리한다.** 질문이 만료돼도 읽은 기록은 행에
      남고, 안 읽었으면 질문이 만료되는 순간 목록에서도 함께 빠진다.
    - **행 자체가 곧 발송 로그다.** 별도 `push_log` 테이블을 두지 않는다. (발송 제한
      3종은 P26으로 전면 폐기됐지만, "언제 무슨 알림을 만들었나"의 기록은 이 테이블 하나로
      충분하다. 로그를 따로 두면 "보냈다고 기록됐는데 목록엔 없는" 상태가 생긴다.)
    - **좌표를 저장하지 않는다.** 필요한 것은 user_id + spot_content_id뿐이다(프라이버시).
    - `spot_content_id`는 presences·reports·bookmarks와 동일하게 TourAPI content_id 원문
      문자열이며 FK가 아니다(로컬 spots 테이블 없음 — 설계 원칙 2).
    - `question_id`에 FK를 걸지 않는다. 알림은 "그때 이런 일이 있었다"는 기록이라 원본
      질문이 사라져도 남아야 하고, FK를 걸면 질문 삭제 기능이 생기는 순간 알림 INSERT가
      질문 트랜잭션을 붙잡는다. 앱이 탭했을 때 질문을 못 찾으면 그때 404를 보여주면 된다.

    채널 중립: 이 테이블에는 전송 수단(웹푸시/FCM/인앱)에 관한 컬럼이 하나도 없다.
    "무슨 일이 있었나"만 담고, "어떻게 밀어 보내나"는 services/notification.py의
    NotificationSender 구현체와 push_subscriptions 테이블이 맡는다(P13/P14).
    """

    __tablename__ = "notifications"
    __table_args__ = (
        # 발송 제한 3종(P26)이 폐기돼 이 복합 인덱스를 쓰던 dedup 판정은 사라졌지만,
        # 인덱스는 남긴다 — 지우려면 마이그레이션이 필요하고(이번 변경은 스키마 무변경),
        # 사용자·관광지·종류별 조회는 앞으로도 쓰일 접근 패턴이다.
        Index("ix_notifications_user_spot_type", "user_id", "spot_content_id", "type"),
        Index("ix_notifications_user_created", "user_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    # 수신자. 알림을 유발한 본인은 여기 들어오지 않는다(P7, services/notification.py에서 제외).
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(20), nullable=False)
    spot_content_id: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    # 탭했을 때 이동할 질문. 두 종류 모두 실제로는 항상 채워지지만, 질문과 무관한 알림
    # 종류가 추가될 여지를 남겨 nullable이다.
    question_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    # 표시 문구. 서버가 코드 상수로 조립해 저장한다(function.md의 motivation_texts 테이블은
    # A/B 테스트용 마스터 데이터라 MVP 범위 밖).
    body: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow, index=True
    )
    # 읽음 처리 시각(naive UTC). null이면 미읽음. 기기 로컬(shared_preferences)이 아니라
    # 서버에 두는 이유는 기기를 바꿔도 이미 본 알림이 다시 뜨지 않게 하기 위함이다.
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    # expires_at property는 없다(2026-09-10 방향 수정, P24). 만료 기준이 알림 자체의
    # 고정 TTL(30분)이 아니라 **연결된 질문의 유효시간(2시간)**으로 바뀌었고, 그 값은
    # questions 행을 조회해야만 알 수 있어서 이 모델 혼자서는 계산할 수 없다.
    # 계산은 services/notification.py의 JOIN 조회(list_active)가 담당한다.
