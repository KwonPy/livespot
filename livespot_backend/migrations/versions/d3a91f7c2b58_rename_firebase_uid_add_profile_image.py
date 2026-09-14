"""users: firebase_uid → auth_provider + provider_user_id, profile_image_url 추가

기능 9(카카오 로그인)의 유일한 마이그레이션이다. 세 가지를 한 리비전으로 묶었다 —
셋 다 users 테이블을 건드리고, SQLite에서는 컬럼 하나를 바꾸는 것도 테이블 재생성이라
나눠 봐야 같은 작업을 세 번 하는 셈이기 때문이다.

1. `firebase_uid` → `provider_user_id` 로 rename
2. `auth_provider` 컬럼 신설 (NOT NULL, 'kakao' | 'test')
3. `profile_image_url` 컬럼 신설 (nullable)

**왜 이름을 바꾸나(쟁점 B):** Firebase를 인증 다리로 쓰지 않기로 확정했다(Q2-A). 그 결정으로
`firebase_uid`는 Firebase와 아무 관계가 없는 값을 담은 컬럼이 된다. 015 일지가 "로그인 붙일 때
스키마 한 번 정리"로 예약해 둔 항목이 이것이다. `firebase-admin` 패키지도 import 0곳이라
requirements.txt에서 함께 제거했다.

**왜 provider를 별도 컬럼으로 두나:** `dev.py`가 테스트유저를 고를 때 예전에는
`firebase_uid.like("seed_user_%")`로 **값의 생김새**를 봤다. 컬럼명이 바뀌면 그 쿼리가
에러 없이 0건을 돌려주고 드롭다운만 조용히 비는, 찾기 어려운 고장이 된다. 판정을
`auth_provider == 'test'`라는 **명시적 값**으로 옮겨 그 자리를 없앤다.

**백필:** 기존 31행(test_user 1 + seed_user_* 30)은 전부 `auth_provider='test'`가 된다.
test_user의 provider_user_id만 'test_firebase_uid' → 'test_user'로 바꾼다(seed.py가
새 DB에 쓰는 값과 맞추기 위함이고, 이 값은 어디에서도 매칭 키로 쓰이지 않는다).

**unique 제약:** `provider_user_id` 단일 컬럼 unique를 그대로 유지한다((provider, id) 복합이
아니다). 이름 없는 UNIQUE 제약을 떼어내는 방식이 SQLite batch 모드와 PostgreSQL에서 서로
달라 위험한 데 비해, provider가 하나뿐인 지금(P1) 복합으로 얻는 것이 없기 때문이다.
카카오 회원번호는 숫자 문자열이고 테스트 id는 'seed_user_NN'이라 충돌하지 않는다.

**방언:** batch_alter_table을 써서 SQLite(로컬)에서도 컬럼 rename이 동작하게 했다.
PostgreSQL(Railway)에서는 batch가 그대로 ALTER TABLE로 내려간다. 적용은 로컬 SQLite에서만
확인했고, Postgres 배포 시 재확인이 필요하다.

Revision ID: d3a91f7c2b58
Revises: b7f3c1e9a204
Create Date: 2026-09-14 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd3a91f7c2b58'
down_revision: Union[str, None] = 'b7f3c1e9a204'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


TEST_USER_ID = "00000000-0000-0000-0000-000000000001"


def upgrade() -> None:
    # auth_provider를 처음부터 NOT NULL로 만들 수 없다(기존 행에 넣을 값이 없다).
    # nullable로 추가 → 백필 → NOT NULL로 조인다. server_default를 쓰지 않은 이유는,
    # 남겨 두면 이후 INSERT가 provider를 생략해도 조용히 통과해서 잘못된 기본값이 박히기 때문이다.
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('auth_provider', sa.String(length=20), nullable=True))
        batch_op.add_column(sa.Column('profile_image_url', sa.String(length=500), nullable=True))
        batch_op.alter_column(
            'firebase_uid',
            new_column_name='provider_user_id',
            existing_type=sa.String(length=128),
            existing_nullable=False,
        )

    # 기존 행은 전부 개발/QA용 사용자다(실제 로그인이 이번에 처음 붙는다).
    op.execute("UPDATE users SET auth_provider = 'test' WHERE auth_provider IS NULL")
    op.execute(
        f"UPDATE users SET provider_user_id = 'test_user' "
        f"WHERE id = '{TEST_USER_ID}' AND provider_user_id = 'test_firebase_uid'"
    )

    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.alter_column(
            'auth_provider',
            existing_type=sa.String(length=20),
            nullable=False,
        )


def downgrade() -> None:
    """되돌리면 **카카오로 가입한 사용자의 provider 구분이 사라진다.**

    컬럼을 지우는 것뿐이라 users 행 자체는 남지만, 되돌린 스키마에서는 카카오 사용자와
    테스트 사용자가 firebase_uid 한 컬럼에 섞여 구분할 수 없다. 실제로 카카오 로그인을
    받은 뒤에는 내려가지 말 것.
    """
    op.execute("UPDATE users SET provider_user_id = 'test_firebase_uid' WHERE id = '%s'" % TEST_USER_ID)

    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.alter_column(
            'provider_user_id',
            new_column_name='firebase_uid',
            existing_type=sa.String(length=128),
            existing_nullable=False,
        )
        batch_op.drop_column('profile_image_url')
        batch_op.drop_column('auth_provider')
