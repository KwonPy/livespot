from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """모든 ORM 모델(Phase 1~8에서 추가될 테이블)이 상속하는 공통 베이스."""
