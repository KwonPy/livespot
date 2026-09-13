import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PushSubscription(Base):
    """푸시 구독 정보. **이번 범위에서는 스키마만 만들고 아무도 쓰지 않는다** (P18, 의도된 상태).

    왜 지금 만드나: 기능 8의 전달 수단은 인앱 폴링이지만(GET /notifications), 나중에
    Web Push나 FCM을 붙일 때 "구독 등록 → 서버 저장 → 서버가 밀어 보냄" 흐름이 필요해진다.
    그때 테이블을 새로 만들면 마이그레이션이 배포와 얽히므로, 컬럼 모양만 미리 못박아 둔다.
    빈 테이블로 남아 있어도 실패가 아니다.

    왜 `device_tokens`가 아닌가(P13/C5): Web Push의 구독은 "토큰" 한 개가 아니라
    endpoint + p256dh/auth 키 쌍이다. `fcm_token` 같은 컬럼명을 쓰면 FCM 전제를 스키마에
    박아 넣게 되고, 웹 푸시를 먼저 붙일 때 컬럼명이 거짓말이 된다. 그래서 채널 중립 이름으로 둔다:

    - `platform`: "web" / "android" / "ios" — 어느 구현체가 이 행을 다룰지 고르는 키
    - `endpoint`: Web Push의 push service URL, FCM이라면 등록 토큰이 들어갈 자리
    - `keys_json`: Web Push의 {p256dh, auth}. FCM처럼 키가 없는 채널이면 null

    구독은 (사용자, endpoint) 단위로 유일하다 — 같은 사람이 브라우저를 여러 개 쓰면
    행이 여러 개 생기는 것이 정상이고, 같은 브라우저가 재구독하면 UPSERT다
    (presences·bookmarks의 UNIQUE 패턴과 동일).
    """

    __tablename__ = "push_subscriptions"
    __table_args__ = (
        UniqueConstraint("user_id", "endpoint", name="uq_push_subscription_user_endpoint"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    platform: Mapped[str] = mapped_column(String(20), nullable=False, default="web")
    # Web Push endpoint는 길다(FCM 경유 시 200자를 넘는다). 잘리면 발송이 조용히 실패하므로 넉넉히 잡는다.
    endpoint: Mapped[str] = mapped_column(String(500), nullable=False)
    keys_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    # 마지막으로 이 구독으로 발송에 성공한 시각. 만료된 구독을 정리할 때 쓸 자리.
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
