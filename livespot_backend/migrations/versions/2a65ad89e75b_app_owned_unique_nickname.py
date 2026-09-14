"""users.nickname: 앱 전용 닉네임으로 전환 (nullable + named unique + 카카오 값 초기화)

2026-09-14. 016(카카오 로그인)의 P22를 뒤집는 후속 변경의 유일한 마이그레이션이다.
닉네임의 **출처**가 카카오에서 사용자 입력으로 바뀌고, **중복 허용**이 unique로 바뀐다.

네 가지를 한 리비전에 묶었다 — 전부 users 테이블을 건드리고, SQLite에서는 컬럼 하나를
바꾸는 것도 테이블 재생성이라 나눠 봐야 같은 작업을 네 번 하는 셈이다.

  ① **중복 사전 검사** — unique를 걸기 *전에* 중복 닉네임을 조회해, 있으면 한국어 메시지로
     명확히 실패시킨다.
  ② `nickname`을 nullable로 전환 (P25 — 미설정 상태의 유일한 표현)
  ④ `auth_provider='kakao'` 행의 nickname을 NULL로 초기화 (Q5-A)
  ③ `uq_users_nickname` **이름 있는** unique 제약 추가 (P31)

**실행 순서가 ①②④③인 것이 중요하다** (번호는 명세 순서, 실행은 이 순서다).
②보다 ④가 앞서면 아직 NOT NULL인 컬럼에 NULL을 쓰는 셈이고, ③이 ④보다 앞서면
겹치는 카카오 닉네임이 남은 채로 unique를 거는 셈이 된다.

## ①이 왜 필요한가 — 이게 이 파일에서 가장 중요한 부분이다

로컬 SQLite는 실측으로 중복 0건이지만(전체 32행), **Railway PostgreSQL은 미검증이다**
(016 한계 2). 배포 DB에 중복이 있으면 ③에서 원시 `IntegrityError`가 터지는데, 그 메시지는
"UNIQUE constraint failed: users.nickname"뿐이라 **어느 닉네임이 몇 개인지 알려주지 않는다.**
배포 중에 그 상태를 만나면 원인을 찾는 데만 한참 걸린다. 그래서 먼저 조회해서
**중복 닉네임 목록을 담은 문장으로 죽인다.** 이때는 아무것도 바뀌지 않은 상태다(①이
②·③보다 앞에 있는 이유).

카카오 사용자는 ④에서 어차피 NULL이 되므로 중복 검사에서 **제외한다** — 카카오 닉네임끼리
겹친다는 이유로 마이그레이션을 막을 필요가 없다.

## ④에서 test_user·seed_user_*를 건드리지 않는 이유

`dev.py`가 `order_by(User.nickname)`으로 테스트유저 드롭다운을 그린다. 이 31행의 닉네임을
NULL로 밀면 **다인원 QA의 유일한 진입점이 깨진다**(016 8-2와 같은 계열의 사고).
게다가 이 값들은 애초에 카카오에서 온 값이 아니라 seed가 정한 고유값이라, "앱 닉네임은
사용자가 고른 값"이라는 불변식을 어기지도 않는다. 그래서 `auth_provider='kakao'` 조건을
명시적으로 건다 — `WHERE nickname IS NOT NULL` 같은 넓은 조건을 쓰지 않는다.

## 방언

`batch_alter_table`을 써서 SQLite(로컬)에서도 컬럼 변경·제약 추가가 동작하게 했다.
PostgreSQL(Railway)에서는 batch가 그대로 ALTER TABLE로 내려간다.
**제약에 이름을 준 것이 downgrade의 전제다**(P31) — 이름 없는 UNIQUE는 SQLite batch
모드에서 떼어낼 수 없다.

Revision ID: 2a65ad89e75b
Revises: d3a91f7c2b58
Create Date: 2026-09-14

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2a65ad89e75b'
down_revision: Union[str, None] = 'd3a91f7c2b58'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


UNIQUE_NAME = "uq_users_nickname"


def _assert_no_duplicate_nicknames() -> None:
    """unique를 걸기 전에 중복을 찾아 사람이 읽을 수 있는 문장으로 실패시킨다.

    카카오 사용자는 아래 ④에서 NULL이 되므로 검사 대상에서 뺀다.
    """
    conn = op.get_bind()
    rows = conn.execute(
        sa.text(
            "SELECT nickname, COUNT(*) AS c FROM users "
            "WHERE nickname IS NOT NULL AND auth_provider <> 'kakao' "
            "GROUP BY nickname HAVING COUNT(*) > 1 "
            "ORDER BY c DESC, nickname"
        )
    ).fetchall()

    if rows:
        detail = ", ".join(f"'{r[0]}'({r[1]}건)" for r in rows)
        raise RuntimeError(
            "users.nickname에 unique 제약을 걸 수 없습니다 — 중복된 닉네임이 있습니다: "
            f"{detail}. "
            "이 마이그레이션은 아무것도 변경하지 않고 중단됐습니다. "
            "중복된 행의 닉네임을 직접 수정하거나 NULL로 비운 뒤 다시 실행하세요 "
            "(NULL은 여러 행이 가져도 unique 제약에 걸리지 않습니다)."
        )


def upgrade() -> None:
    # ① 먼저 확인한다. 여기서 죽으면 DB는 그대로다.
    _assert_no_duplicate_nicknames()

    # ② nullable 전환이 **먼저**다. 순서를 ④와 바꾸면 아직 NOT NULL인 컬럼에 NULL을 넣는
    #    셈이라 `NOT NULL constraint failed: users.nickname`으로 죽는다. (실제로 겪었다.)
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.alter_column(
            'nickname',
            existing_type=sa.String(length=50),
            nullable=True,
        )

    # ④ 카카오 사용자의 닉네임을 비운다(Q5-A). 이것도 ③보다 앞이어야 한다 — 카카오
    #    닉네임끼리 겹쳐 있어도(지금까지는 중복 허용이었다) 먼저 NULL이 되면 unique가
    #    문제없이 걸린다. test_user·seed_user_*는 건드리지 않는다(위 설명 참조).
    op.execute("UPDATE users SET nickname = NULL WHERE auth_provider = 'kakao'")

    # ③ 이름 있는 unique 추가. SQLite에서는 이 batch가 테이블 재생성이다.
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.create_unique_constraint(UNIQUE_NAME, ['nickname'])


def downgrade() -> None:
    """되돌리면 **NULL이던 닉네임에 자리표시값이 들어간다** — 원래 값은 복구되지 않는다.

    `nickname`을 NOT NULL로 되돌리려면 NULL 행이 하나도 없어야 한다. 그런데 upgrade의 ④가
    카카오 사용자의 닉네임을 **버렸기 때문에**(원본을 어디에도 보관하지 않았다) 복원할
    값이 없다. 그래서 여기서는 스키마만 되돌리고, 값은 `user_<id 앞 8자>` 형태의
    고유한 자리표시값으로 채운다 — NOT NULL과 (되돌리기 전의) 중복 허용 양쪽을 만족시키는
    최소한의 값이다.

    **즉 이 downgrade는 스키마 왕복 검증용이지 데이터 복구 수단이 아니다.**
    실제로 카카오 로그인을 받은 뒤에는 내려가지 말 것(016 d3a91f7c2b58의 경고와 같은 성격).

    닉네임을 실제로 잃고 싶지 않다면, upgrade 전에 users 테이블을 덤프해 두는 것이
    유일한 방법이다.
    """
    # NOT NULL로 조이기 전에 NULL을 먼저 없애야 한다. 순서를 바꾸면 여기서 터진다.
    op.execute(
        "UPDATE users SET nickname = 'user_' || substr(id, 1, 8) WHERE nickname IS NULL"
    )

    with op.batch_alter_table('users', schema=None) as batch_op:
        # 이름이 있어서 뗄 수 있다(P31). 이름이 없었다면 SQLite에서 이 줄이 불가능하다.
        batch_op.drop_constraint(UNIQUE_NAME, type_='unique')
        batch_op.alter_column(
            'nickname',
            existing_type=sa.String(length=50),
            nullable=False,
        )
