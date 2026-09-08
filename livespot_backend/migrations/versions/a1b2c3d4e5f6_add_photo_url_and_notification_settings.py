"""add photo_url to reports and spot_notification_settings table

Revision ID: a1b2c3d4e5f6
Revises: 038a46869fc7
Create Date: 2026-08-21 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = '038a46869fc7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('reports', sa.Column('photo_url', sa.String(length=500), nullable=True))

    op.create_table(
        'spot_notification_settings',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('user_id', sa.String(length=36), nullable=False),
        sa.Column('spot_content_id', sa.String(length=20), nullable=False),
        sa.Column('push_enabled', sa.Boolean(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'spot_content_id', name='uq_notification_setting_user_spot'),
    )
    op.create_index(
        op.f('ix_spot_notification_settings_spot_content_id'),
        'spot_notification_settings', ['spot_content_id'], unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f('ix_spot_notification_settings_spot_content_id'),
        table_name='spot_notification_settings',
    )
    op.drop_table('spot_notification_settings')
    op.drop_column('reports', 'photo_url')
