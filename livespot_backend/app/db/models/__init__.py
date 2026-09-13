# Phase 2+에서 로그인/제보/Credit 등 사용자 데이터 테이블이 추가되면 여기서 import
from app.db.models.user import User  # noqa: F401
from app.db.models.report import Report  # noqa: F401
from app.db.models.notification_setting import NotificationSetting  # noqa: F401
from app.db.models.question import Question  # noqa: F401
from app.db.models.answer import Answer  # noqa: F401
from app.db.models.credit_ledger import CreditLedger  # noqa: F401
from app.db.models.bookmark import Bookmark  # noqa: F401
from app.db.models.presence import Presence  # noqa: F401
from app.db.models.notification import Notification  # noqa: F401
from app.db.models.push_subscription import PushSubscription  # noqa: F401

# `user_notification_setting.UserNotificationSetting`(기능 8 전역 알림 스위치)은
# 2026-09-13에 삭제됐다(015 Q3=B). 테이블도 마이그레이션 `b7f3c1e9a204`로 드롭됐다.
# 여기 import가 남아 있으면 Alembic autogenerate가 테이블을 다시 만들려 하므로 함께 지운다.
