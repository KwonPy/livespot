"""drop_user_notification_settings

기능 8의 **전역 알림 on/off 스위치를 폐기**한다(2026-09-13 정책 축소, 015 N1·N2·Q3=B).

무엇이 사라지나: `user_notification_settings` 테이블 하나뿐이다. 같은 리비전
`1d90a3fa7298`이 함께 만든 `notifications`·`push_subscriptions`는 **그대로 둔다** —
알림 기능 자체(NEW_ANSWER)는 계속 살아 있다.

왜 `1d90a3fa7298`의 downgrade()를 쓰지 않았나: 그 함수는 세 테이블을 **한꺼번에** 드롭한다.
실행하면 답변 알림 데이터와 스키마까지 같이 날아간다. 그래서 되돌리지 않고 그 위에 이
리비전을 쌓아 필요한 테이블 하나만 드롭한다.

왜 지우나: 토글 UI(`my_qna_screen.dart`)와 `GET/POST /api/notifications/push-settings`가
제거돼 아무도 읽지 않는 테이블이 됐다. 그런데 **행을 남겨 두면 위험하다** — 과거에 OFF를
저장한 사용자가 있으면, 코드가 그 값을 안 읽게 된 지금은 무해하지만 나중에 누군가
`_disabled_user_ids` 류의 조회를 되살렸을 때 "본인은 켠 적도 끈 적도 없는데 알림이 안 오는"
상태가 되살아난다. 스키마를 정직하게 유지하는 쪽을 택했다.

downgrade()는 테이블을 **원래 모양 그대로** 다시 만든다(행 데이터는 복구할 수 없다 —
드롭된 행은 어디에도 남아 있지 않다). `1d90a3fa7298`의 create_table과 컬럼·제약·인덱스가
동일해야 왕복이 성립하므로 그쪽에서 그대로 옮겨 왔다.

타입은 String/Boolean/DateTime만 써서 SQLite(로컬)·PostgreSQL(Railway) 양쪽에서 돈다.
이번 작업은 로컬 SQLite에만 적용했고 Postgres 배포는 범위 밖이다.

Revision ID: b7f3c1e9a204
Revises: 1d90a3fa7298
Create Date: 2026-09-13 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7f3c1e9a204'
down_revision: Union[str, None] = '1d90a3fa7298'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 인덱스를 먼저 떨군다. SQLite는 drop_table이 인덱스를 같이 정리하지만,
    # PostgreSQL에서도 순서를 명시해 두는 편이 방언 간 동작이 예측 가능하다.
    op.drop_index(
        op.f('ix_user_notification_settings_user_id'),
        table_name='user_notification_settings',
    )
    op.drop_table('user_notification_settings')


def downgrade() -> None:
    op.create_table(
        'user_notification_settings',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('user_id', sa.String(length=36), nullable=False),
        sa.Column('push_enabled', sa.Boolean(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_user_notification_setting_user'),
    )
    op.create_index(
        op.f('ix_user_notification_settings_user_id'),
        'user_notification_settings',
        ['user_id'],
        unique=False,
    )
