import uuid
from datetime import datetime

from sqlalchemy import DateTime, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# auth_provider가 가질 수 있는 값. 새 provider를 늘리는 것은 P1(로그인 수단은 카카오 하나)
# 위반이므로, 늘리기 전에 명세부터 고칠 것.
PROVIDER_KAKAO = "kakao"
PROVIDER_TEST = "test"   # seed.py가 만드는 test_user / seed_user_* 전용 (TEST_MODE에서만 쓰임)


class User(Base):
    """서비스 사용자 (기능 1/9 카카오 로그인).

    **id는 서버가 만든 UUID 문자열이고, 카카오 회원번호를 PK로 쓰지 않는다**(P4·P8).
    9개 테이블이 이 값을 FK로 물고 있어서, 여기가 흔들리면 제보·크레딧·북마크가 통째로 갈린다.
    카카오 회원번호는 (auth_provider, provider_user_id) 쌍으로만 보관하고 응답에 싣지 않는다.

    2026-09-14(기능 9): `firebase_uid` 컬럼을 `auth_provider` + `provider_user_id`로 정리했다
    (마이그레이션 d3a91f7c2b58). Firebase를 다리로 쓰지 않기로 확정(Q2-A)했으므로 그 이름이
    거짓이 됐기 때문이다. seed 사용자는 auth_provider='test'로 구분한다 —
    dev.py가 예전에 쓰던 `firebase_uid.like("seed_user_%")` 문자열 매칭보다 정확하다
    (카카오 회원번호가 우연히 seed_user_로 시작할 일은 없지만, 판정을 값의 생김새에
    의존시키지 않는 편이 낫다).
    """

    __tablename__ = "users"

    # 이름을 명시한 unique 제약(P31). NULL은 여러 행이 가질 수 있다 — SQLite·PostgreSQL 모두
    # UNIQUE가 NULL끼리는 충돌로 보지 않으므로, "닉네임 미설정 사용자"가 여럿이어도 문제없다.
    __table_args__ = (UniqueConstraint("nickname", name="uq_users_nickname"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))

    # 어느 인증 수단으로 만들어진 계정인가. "kakao" | "test"
    auth_provider: Mapped[str] = mapped_column(String(20), nullable=False, default=PROVIDER_KAKAO)

    # 그 provider가 부여한 식별자. 카카오면 회원번호(숫자 문자열), test면 "test_user"/"seed_user_N".
    # unique를 (provider, id) 복합이 아니라 단일 컬럼에 건 이유: SQLite에서 기존 unique 제약을
    # 이름 없이 떼어내는 마이그레이션이 방언마다 갈려 위험하고, P1대로 provider가 하나뿐이라
    # 실익이 없다. 두 번째 provider가 생기면 그때 복합 unique로 옮긴다.
    provider_user_id: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)

    # **앱 전용 닉네임 — 사용자가 직접 입력한 값이다**(P23, 2026-09-14. P22 폐기).
    #
    # nullable인 이유(P25): "아직 닉네임을 안 정했다"를 표현할 방법이 이것뿐이어야 한다.
    # `nickname_set` 같은 불리언을 따로 두면 같은 사실의 출처가 둘이 되고, 016의 F2·F3가
    # 정확히 그 계열의 버그였다(한쪽만 갱신돼 화면과 DB가 어긋남).
    #
    # unique인 이유(P24): "중복도 당연히 방지해야" — 사용자 정책. 다만 이건 **표시 계층의
    # 제약**이지 식별 체계의 변경이 아니다. **어떤 쿼리도 nickname으로 사용자를 조회·매칭·
    # 조인하지 않는다.** FK는 전부 users.id(UUID)를 그대로 본다.
    #
    # 제약에 `uq_users_nickname`이라는 **이름을 준 것이 핵심이다**(P31). 이름이 없으면
    # SQLite batch 모드에서 떼어낼 수 없어 downgrade가 불가능해진다(016 9-8의 교훈).
    # 대소문자를 구분하는 원문 그대로의 unique다 — `lower(nickname)` 함수 인덱스는 SQLite와
    # PostgreSQL에서 표현이 갈려 쓰지 않는다.
    #
    # 컬럼 길이는 String(50) 그대로 둔다. 검증(services/nickname.py)에서만 12자로 자른다 —
    # 컬럼 축소 마이그레이션은 위험 대비 이득이 없다.
    # (unique 제약은 아래 __table_args__에서 이름과 함께 선언한다 — `unique=True`를 여기
    #  쓰면 이름 없는 제약이 만들어져 SQLite에서 떼어낼 수 없다.)
    nickname: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # **앞으로 항상 NULL이다**(P39·P40). 카카오 동의항목(profile_image)을 받지 않기로
    # 확정돼 채울 값이 없다. 그런데도 컬럼을 남기는 이유: 앱 자체 프로필 이미지 업로드가
    # 붙을 때 이 자리가 그대로 쓰인다(images.py 라우터가 이미 있다). 지우면 마이그레이션 +
    # 응답 스키마 + Dart 모델 + 아바타 위젯이 **함께** 바뀌는데, 얻는 것은 빈 컬럼 하나가
    # 사라지는 것뿐이다.
    profile_image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)

    credit_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    trust_level: Mapped[str] = mapped_column(String(20), nullable=False, default="NEWCOMER")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
