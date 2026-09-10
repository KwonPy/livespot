"""현장 Q&A 조회 규칙을 한 곳에 모은 모듈 (기능 7 · 기능 6에서 재사용).

`GET /questions?spot_content_id=&pending_only=true&active_only=true`가 돌려주는
"답변 대기 질문" 목록은, 위치 신호 응답(`POST /reports/verify-location`)이 함께 실어
보내는 목록과 **정확히 같은 것**이어야 한다. 웹에는 푸시가 없어 이 동봉 목록이 사실상
답변 유도의 주 전달 경로인데, 두 곳이 각자 쿼리를 짜면 상세페이지 Q&A 탭에는 떠 있는
질문이 배너에는 안 뜨는(또는 그 반대) 상태가 생긴다.

그래서 라우터에 있던 stmt 구성과 응답 조립을 여기로 내리고, api/questions.py와
api/reports.py가 같은 함수를 부른다. "오늘(KST)" 정의는 services/report_window.py의
today_cutoff_utc()를 공유한다 — 하루 경계가 LIVE·브리핑과 갈리면 안 된다.
"""

from datetime import datetime, timedelta
from typing import List, Optional, Sequence, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.answer import Answer
from app.db.models.question import Question, QUESTION_TTL_HOURS
from app.db.models.user import User
from app.models.schemas import AnswerResponse, QuestionResponse
from app.services.report_window import today_cutoff_utc


def question_status(question: Question) -> str:
    """ACTIVE/EXPIRED는 저장값이 아니라 조회 시점 계산이다(created_at + TTL)."""
    return (
        "EXPIRED"
        if datetime.utcnow() >= question.created_at + timedelta(hours=QUESTION_TTL_HOURS)
        else "ACTIVE"
    )


async def build_question_response(
    db: AsyncSession, question: Question, asker_nickname: str
) -> QuestionResponse:
    """질문 1건 + 그 답변 목록을 응답 모델로 조립한다."""
    result = await db.execute(
        select(Answer, User.nickname)
        .join(User, Answer.user_id == User.id)
        .where(Answer.question_id == question.id)
        .order_by(Answer.created_at.asc())
    )
    answers = [
        AnswerResponse(
            id=a.id,
            question_id=a.question_id,
            user_id=a.user_id,
            user_nickname=nickname,
            content=a.content,
            created_at=a.created_at,
        )
        for a, nickname in result.all()
    ]
    return QuestionResponse(
        id=question.id,
        user_id=question.user_id,
        user_nickname=asker_nickname,
        spot_content_id=question.spot_content_id,
        content=question.content,
        status=question_status(question),
        answer_count=question.answer_count,
        created_at=question.created_at,
        expires_at=question.created_at + timedelta(hours=QUESTION_TTL_HOURS),
        answers=answers,
    )


async def fetch_spot_questions(
    db: AsyncSession,
    spot_content_id: str,
    *,
    pending_only: bool = False,
    active_only: bool = False,
    limit: Optional[int] = None,
) -> Sequence[Tuple[Question, str]]:
    """관광지별 질문 목록 (오늘=KST 자정 기준, 최신순)과 작성자 닉네임.

    active_only=True면 만료(EXPIRED)된 질문 제외, pending_only=True면 추가로 답변이
    하나도 없는 질문만. 이 조합(pending+active)이 곧 "답변 대기 질문"의 정의다.
    """
    stmt = (
        select(Question, User.nickname)
        .join(User, Question.user_id == User.id)
        .where(
            Question.spot_content_id == spot_content_id,
            Question.created_at >= today_cutoff_utc(),
        )
        .order_by(Question.created_at.desc())
    )
    if pending_only or active_only:
        stmt = stmt.where(
            Question.created_at >= datetime.utcnow() - timedelta(hours=QUESTION_TTL_HOURS)
        )
    if pending_only:
        stmt = stmt.where(Question.answer_count == 0)
    if limit is not None:
        stmt = stmt.limit(limit)

    result = await db.execute(stmt)
    return result.all()


async def fetch_pending_questions(
    db: AsyncSession, spot_content_id: str, limit: int
) -> List[QuestionResponse]:
    """위치 신호 응답에 동봉할 "지금 답변을 기다리는 질문" 상위 N건.

    상세페이지 Q&A 탭의 pending_only=true&active_only=true 목록과 같은 쿼리를 쓴다 —
    두 화면이 다른 목록을 보여주지 않게 하려고 일부러 함수를 공유한다.
    """
    rows = await fetch_spot_questions(
        db, spot_content_id, pending_only=True, active_only=True, limit=limit
    )
    return [await build_question_response(db, question, nickname) for question, nickname in rows]
