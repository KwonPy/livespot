from datetime import datetime, timedelta
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.db.models.question import Question, QUESTION_TTL_HOURS
from app.db.models.answer import Answer
from app.db.models.user import User
from app.api.deps import get_current_user_id
from app.models.schemas import (
    QuestionCreate,
    QuestionResponse,
    AnswerCreate,
    AnswerResponse,
    MyAnswerEntry,
    MyQuestionEntry,
)
from app.services.tour_api import TourAPIService
from app.services.geo import calculate_distance_m
from app.services import credit as credit_service
from app.services import notification as notification_service
from app.services.spot_lookup import resolve_spot_names
from app.services.question_query import (
    build_question_response as _to_response,
    fetch_spot_questions,
    question_status as _status,
)

router = APIRouter()
tour_service = TourAPIService()

# live.py의 _today_cutoff_utc와 동일한 KST 자정 환산 로직 — "질문 목록은 하루 단위로
# 리셋"(정책)을 조회 필터로 구현한다. 과거 질문은 DB에 그대로 남고, 오늘(KST) 등록된
# 것만 목록에 노출된다.
_KST_OFFSET = timedelta(hours=9)


def _kst_today_start_utc() -> datetime:
    now_kst = datetime.utcnow() + _KST_OFFSET
    start_of_today_kst = datetime(now_kst.year, now_kst.month, now_kst.day)
    return start_of_today_kst - _KST_OFFSET


# _status(만료 판정)와 _to_response(질문+답변 조립)는 services/question_query.py로 옮겼다.
# 위치 신호 응답(POST /reports/verify-location)이 "답변 대기 질문"을 동봉하는데(기능 6),
# 그 목록이 아래 GET /questions?pending_only=true 와 정확히 같아야 하기 때문이다 —
# 라우터에 두면 reports.py가 questions.py를 import하게 되고, 복붙하면 두 목록이 갈라진다.
# 동작은 이전과 동일하다(이름도 그대로 유지해 호출부는 손대지 않았다).


@router.post("", response_model=QuestionResponse)
async def create_question(
    payload: QuestionCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """질문 등록. 위치 제한이 없다 — 질문자는 원래 멀리 있는 사람 (function.md 기능 3①).
    관광지 상세페이지에서만 여는 걸 전제로 하지만, 그 제약은 앱(UI) 쪽에서 지킨다."""
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=500, detail="사용자가 초기화되지 않았습니다")

    # 알림(기능 8) 대상 판정을 **db.add(question)보다 먼저** 부른다. 판정 안에서 presences
    # SELECT가 돌기 때문에, 세션에 pending 객체가 있으면 autoflush가 끼어들어 아직 완성되지
    # 않은 질문 행을 먼저 INSERT 하려 든다(credit.prepare_award와 같은 제약).
    #
    # 2026-09-13: 이 호출을 한 번 제거했다가 같은 날 복원했다(015 2-2절 사용자 정정).
    # "인앱 알림 목록 *페이지*를 없애라"를 "NEW_QUESTION 알림을 만들지 말라"로 잘못 읽은
    # 결과, 현장 사용자에게 뜨던 실시간 모달까지 같이 사라졌다 — 모달·배지·목록이 전부
    # 같은 알림 행 하나에서 갈라지기 때문이다. 지우지 말 것.
    pending_alerts = await notification_service.prepare_new_question(
        db,
        spot_content_id=payload.spot_content_id,
        actor_user_id=user_id,
    )

    question = Question(
        user_id=user_id,
        spot_content_id=payload.spot_content_id,
        content=payload.content,
    )
    db.add(question)
    # 알림 행에 question_id를 채우려면 id가 먼저 필요하다. commit까지 기다리지 않고 flush로
    # INSERT만 당겨 받는다 — 알림 INSERT를 질문과 같은 트랜잭션에 묶기 위함이다(P6).
    await db.flush()

    alert_rows = pending_alerts.build(question_id=question.id)
    db.add_all(alert_rows)
    await db.commit()
    await db.refresh(question)

    # 전달(WS 깨우기)은 commit 이후에. 실패해도 예외를 삼킨다 — 알림 행은 이미 저장됐다.
    await notification_service.deliver(db, alert_rows)

    return await _to_response(db, question, user.nickname)


@router.get("/recent", response_model=List[QuestionResponse])
async def get_recent_questions(limit: int = 10, db: AsyncSession = Depends(get_db)):
    """Live 페이지의 "전체 LIVE Q&A" — 관광지 구분 없이 오늘(KST) 등록된 활성(ACTIVE) 질문 중
    최신순. 이 목록에서는 정책상 누구도 답변할 수 없다 — 답변은 "내 현장 Q&A"(GPS 인증된
    관광지)나 관광지 상세페이지 Q&A에서만 가능하다(questions.py 답변 엔드포인트가 그대로
    그 두 화면에서만 호출되고, 이 엔드포인트는 조회 전용이다)."""
    today_cutoff = _kst_today_start_utc()
    not_expired_cutoff = datetime.utcnow() - timedelta(hours=QUESTION_TTL_HOURS)
    stmt = (
        select(Question, User.nickname)
        .join(User, Question.user_id == User.id)
        .where(Question.created_at >= today_cutoff, Question.created_at >= not_expired_cutoff)
        .order_by(Question.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    return [await _to_response(db, question, nickname) for question, nickname in result.all()]


@router.get("", response_model=List[QuestionResponse])
async def get_questions(
    spot_content_id: str,
    pending_only: bool = False,
    active_only: bool = False,
    db: AsyncSession = Depends(get_db),
):
    """관광지 상세페이지·Live 페이지("내 현장 Q&A")의 현장 Q&A 목록. 오늘(KST) 등록된
    질문만 보여준다(정책: 질문 목록은 하루 단위로 리셋 — 조회 필터일 뿐, 만료된 질문도
    오늘 안이면 그대로 보인다. 답변은 이미 만료된 질문에는 새로 달 수 없을 뿐 조회는 계속 된다).

    active_only=True면 만료(EXPIRED)된 질문을 제외한다 — Live 페이지의 "내 현장 Q&A"는
    활성 질문만 보여주는 정책이라 사용. 상세페이지는 기본값(False)으로 만료 질문도 "만료"
    배지와 함께 계속 보여준다.
    pending_only=True면 추가로 답변이 하나도 없는 질문만 돌려준다.

    쿼리 본체는 services/question_query.fetch_spot_questions에 있다 — 위치 신호 응답의
    "답변 대기 질문" 배너(기능 6)가 같은 함수를 부르기 위함이다.
    """
    rows = await fetch_spot_questions(
        db, spot_content_id, pending_only=pending_only, active_only=active_only
    )
    return [await _to_response(db, question, nickname) for question, nickname in rows]


@router.get("/me", response_model=List[MyQuestionEntry])
async def get_my_questions(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """마이 화면 "내 Q&A" 중 질문 탭(기능 12). 스팟별 조회(`GET /questions`)와 달리
    "오늘(KST)" 필터가 없다 — 개인 활동 이력이라 지난 질문도 계속 보여야 한다."""
    result = await db.execute(
        select(Question).where(Question.user_id == user_id).order_by(Question.created_at.desc())
    )
    questions = result.scalars().all()
    names = await resolve_spot_names({q.spot_content_id for q in questions})

    entries = []
    for question in questions:
        answers_result = await db.execute(
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
            for a, nickname in answers_result.all()
        ]
        entries.append(
            MyQuestionEntry(
                id=question.id,
                spot_content_id=question.spot_content_id,
                spot_name=names.get(question.spot_content_id),
                content=question.content,
                status=_status(question),
                answer_count=question.answer_count,
                created_at=question.created_at,
                expires_at=question.created_at + timedelta(hours=QUESTION_TTL_HOURS),
                answers=answers,
            )
        )
    return entries


@router.get("/me/answers", response_model=List[MyAnswerEntry])
async def get_my_answers(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """마이 화면 "내 Q&A" 중 답변 탭(기능 12). 내 답변만으로는 무슨 질문에 단 것인지 알 수
    없어 원 질문(content·spot_content_id)을 조인해 함께 내려준다."""
    result = await db.execute(
        select(Answer, Question)
        .join(Question, Answer.question_id == Question.id)
        .where(Answer.user_id == user_id)
        .order_by(Answer.created_at.desc())
    )
    rows = result.all()
    names = await resolve_spot_names({question.spot_content_id for _, question in rows})
    return [
        MyAnswerEntry(
            id=answer.id,
            question_id=question.id,
            spot_content_id=question.spot_content_id,
            spot_name=names.get(question.spot_content_id),
            question_content=question.content,
            content=answer.content,
            created_at=answer.created_at,
        )
        for answer, question in rows
    ]


@router.post("/{question_id}/answers", response_model=AnswerResponse)
async def create_answer(
    question_id: str,
    payload: AnswerCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """답변 등록. GPS 현장 인증(기능 3)이 되어야만 가능 — 제보와 동일한 판정 기준
    (반경 100m + 오차 50m)을 재사용해, 매번 서버가 거리를 다시 계산한다(정책).
    관광지 상세페이지·Live 페이지 양쪽에서 동일하게 이 엔드포인트를 호출한다."""
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=500, detail="사용자가 초기화되지 않았습니다")

    question = await db.get(Question, question_id)
    if question is None:
        raise HTTPException(status_code=404, detail="질문을 찾을 수 없습니다")

    if question.user_id == user_id:
        raise HTTPException(status_code=403, detail="본인이 작성한 질문에는 답변할 수 없습니다")

    if _status(question) == "EXPIRED":
        raise HTTPException(status_code=400, detail="만료된 질문에는 답변할 수 없습니다")

    spot = await tour_service.get_spot_detail(question.spot_content_id)
    if not spot:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다")

    spot_lat = float(spot.get("mapy", 0))
    spot_lng = float(spot.get("mapx", 0))
    distance = calculate_distance_m(payload.lat, payload.lng, spot_lat, spot_lng)

    threshold = settings.GPS_VERIFICATION_RADIUS_M + settings.GPS_ERROR_MARGIN_M
    is_verified = distance <= threshold

    if not is_verified and not settings.DEMO_BYPASS_GPS:
        raise HTTPException(
            status_code=403,
            detail=f"현재 위치에서 {int(distance)}m 떨어져 있어요. 관광지 반경 {threshold}m 이내에서만 답변할 수 있습니다.",
        )

    # 적립 판정을 db.add(answer)보다 먼저 부른다 — 판정이 SELECT를 돌리므로 pending 객체가
    # 있으면 autoflush가 끼어든다. source_id는 answer.id가 아니라 question_id라서 답변 id에
    # 의존하지 않고, 그래서 미리 판정할 수 있다.
    ledger = await credit_service.prepare_answer_award(
        db, user,
        question_id=question_id,
        spot_content_id=question.spot_content_id,
        gps_verified=is_verified,
    )

    # 알림(기능 8)도 같은 이유로 db.add(answer) 앞에서 판정한다. 수신자는 질문자 1명이고,
    # question_id를 이미 알고 있어 여기서 바로 행까지 만들 수 있다(질문 등록 경로와 달리
    # flush를 기다릴 필요가 없다).
    alert_rows = (
        await notification_service.prepare_new_answer(
            db,
            spot_content_id=question.spot_content_id,
            question_owner_id=question.user_id,
            actor_user_id=user_id,
            answer_content=payload.content,
        )
    ).build(question_id=question_id)

    answer = Answer(
        question_id=question_id,
        user_id=user_id,
        content=payload.content,
        gps_verified=is_verified,
    )
    db.add(answer)
    question.answer_count += 1
    if ledger is not None:
        # 이미 답변·카운트 갱신이 한 트랜잭션이므로, 여기에 원장 행을 얹으면 트랜잭션
        # 경계가 자동으로 지켜진다. 같은 질문에 두 번째 답변부터는 ledger가 None이고
        # (질문당 1회, P14) 답변 자체는 정상 저장된다.
        db.add(ledger)
    # 알림도 같은 트랜잭션에 얹는다(P6). 대상이 없으면 빈 리스트라 아무 일도 하지 않는다.
    db.add_all(alert_rows)
    await db.commit()
    await db.refresh(answer)

    await notification_service.deliver(db, alert_rows)

    return AnswerResponse(
        id=answer.id,
        question_id=answer.question_id,
        user_id=answer.user_id,
        user_nickname=user.nickname,
        content=answer.content,
        created_at=answer.created_at,
    )
