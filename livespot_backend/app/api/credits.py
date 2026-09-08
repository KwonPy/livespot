from typing import List

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_id
from app.db.session import get_db
from app.models.schemas import (
    ActivityCountResponse,
    CreditLedgerEntry,
    CreditSummaryResponse,
)
from app.services import credit as credit_service

router = APIRouter()

# 이 라우터는 **조회 전용**이다. 적립은 제보(api/reports.py)·답변(api/questions.py)이
# 저장되는 트랜잭션 안에서만 일어난다 — 크레딧을 올리는 엔드포인트를 따로 열어두면
# 아무 근거 없이 크레딧을 발급하는 경로가 생긴다.
#
# "me"는 전부 deps.get_current_user_id()가 돌려주는 사용자다. 로그인(기능 1)이 붙으면
# 그 함수 하나만 바뀌고 여기는 그대로다.


@router.get("/me", response_model=CreditSummaryResponse)
async def get_my_credit(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """잔액·누적·현재 뱃지. 아직 아무 활동이 없어도 200 + 0 + 최하위 뱃지를 돌려준다 —
    빈 상태는 에러가 아니고, 여기서 404를 내면 마이 화면 전체가 못 그려진다."""
    return await credit_service.get_summary(db, user_id)


@router.get("/me/ledger", response_model=List[CreditLedgerEntry])
async def get_my_ledger(
    limit: int = Query(default=20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """적립·회수 내역 최신순. 내역이 없으면 빈 배열([])이다."""
    return await credit_service.get_ledger(db, user_id, limit)


@router.get("/me/activity", response_model=ActivityCountResponse)
async def get_my_activity(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """내 제보·답변·질문 건수. 적립 여부와 무관한 작성 총 건수다 (services/credit.py 참고)."""
    return await credit_service.get_activity(db, user_id)
