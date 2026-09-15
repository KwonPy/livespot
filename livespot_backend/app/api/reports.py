import uuid

from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.db.models.report import Report
from app.db.models.user import User
from app.api.deps import get_current_user_id
from app.models.schemas import (
    CreditSkipReason,
    MyReportEntry,
    QuestionResponse,
    ReportCreate,
    ReportResponse,
    VerifyLocationRequest,
    VerifyLocationResponse,
)
from app.services.tour_api import TourAPIService
from app.services.geo import calculate_distance_m
from app.services import credit as credit_service
from app.services import presence as presence_service
from app.services.nickname import display_nickname
from app.services.question_query import fetch_pending_questions
from app.services.spot_lookup import resolve_spot_names

router = APIRouter()
tour_service = TourAPIService()


def _to_response(
    report: Report,
    nickname: Optional[str],
    *,
    credit_earned: int = 0,
    credit_skip_reason: Optional[CreditSkipReason] = None,
) -> ReportResponse:
    """제보 1건 → 응답. 조인해 온 닉네임은 nullable이다(P25).

    `ReportResponse.user_nickname`은 계속 `str`(비-null)이라 폴백을 씌운다(P33).
    닉네임 미설정 사용자는 제보를 만들 수 없으므로(P28) 실제로는 발동하지 않는다 —
    발동한다면 목록이 500으로 죽는 대신 한 줄만 "알 수 없음"으로 뜨게 하는 안전장치다.

    크레딧 두 인자는 **키워드 전용 + 기본값**이다. 목록 조회(GET /reports, GET 계열)는
    "이번 요청으로 적립된 금액"이라는 개념이 없으므로 그냥 부르면 0/None이 나가고,
    POST 경로만 실제 판정 결과를 넘긴다(011 9절 C6·C10).
    """
    return ReportResponse(
        id=report.id,
        user_id=report.user_id,
        user_nickname=display_nickname(nickname),
        spot_content_id=report.spot_content_id,
        crowdedness_level=report.crowdedness_level,
        waiting_time=report.waiting_time,
        parking_status=report.parking_status,
        comment=report.comment,
        photo_url=report.photo_url,
        gps_verified=report.gps_verified,
        created_at=report.created_at,
        credit_earned=credit_earned,
        credit_skip_reason=credit_skip_reason,
    )


@router.post("", response_model=ReportResponse)
async def create_report(
    report: ReportCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=500, detail="사용자가 초기화되지 않았습니다")

    # 닉네임을 **지금** 지역 변수로 떠둔다. 아래 IntegrityError 경로의 `db.rollback()`이
    # 세션의 모든 객체를 expire 시키는데(expire_on_commit=False라 commit은 안 그런다),
    # 그 뒤에 `user.nickname`을 읽으면 SQLAlchemy가 동기 lazy-load를 시도해
    # MissingGreenlet으로 500이 난다. 동시 중복 제출을 200으로 흡수하려고 만든 폴백이
    # 정작 500을 내던 지점이다. 값만 미리 꺼내두면 rollback 이후 DB 접근이 없어진다.
    nickname = user.nickname

    # 중복 제출: 같은 client_request_id로 이미 저장된 제보가 있으면 새로 만들지 않고 그대로 돌려준다.
    #
    # 크레딧은 0 + ALREADY_AWARDED로 내려간다(011 9절 C11). 원장을 다시 조회해 "이 제보가
    # 원래 받았던 금액"을 돌려주지 않는 이유: 필드 정의가 "이번 요청으로 새로 적립된 금액"
    # 이고, 재제출에 +10을 실으면 모달이 두 번 열린 사용자에게 적립이 두 번 된 것처럼 보인다.
    existing = await db.scalar(select(Report).where(Report.client_request_id == report.client_request_id))
    if existing is not None:
        return _to_response(existing, nickname, credit_skip_reason="ALREADY_AWARDED")

    spot = await tour_service.get_spot_detail(report.spot_content_id)
    if not spot:
        raise HTTPException(status_code=404, detail="Spot not found")

    spot_lat = float(spot.get("mapy", 0))
    spot_lng = float(spot.get("mapx", 0))
    distance = calculate_distance_m(report.lat, report.lng, spot_lat, spot_lng)

    threshold = settings.GPS_VERIFICATION_RADIUS_M + settings.GPS_ERROR_MARGIN_M
    is_verified = distance <= threshold

    if not is_verified and not settings.DEMO_BYPASS_GPS:
        raise HTTPException(
            status_code=403,
            detail=f"현재 위치에서 {int(distance)}m 떨어져 있어요. 관광지 반경 {threshold}m 이내에서만 제보할 수 있습니다.",
        )

    # id를 미리 발급하는 이유: 크레딧 원장의 source_id로 써야 하는데, 적립 자격 판정이
    # SELECT를 돌리므로 db.add(new_report) 뒤에 부르면 autoflush가 일어난다. 그러면 아래
    # try/except IntegrityError가 잡아야 할 client_request_id 중복 예외가 try 블록 밖에서
    # 터져 "중복 제출 시 기존 제보를 그대로 돌려준다"는 관례가 깨진다.
    report_id = str(uuid.uuid4())

    # 적립은 여기서 판정만 하고 add는 아래 commit 앞에서 한다. 자격이 없으면(GPS 미인증,
    # 같은 장소 하루 상한 초과) award.ledger가 None이지만 제보 자체는 그대로 저장되고
    # HTTP 200이다 — 크레딧을 못 받았다고 정보 제공을 막지는 않는다(011 9절 C2).
    # 판정 결과(금액 또는 사유)는 응답의 credit_earned/credit_skip_reason으로 그대로 나간다.
    award = await credit_service.prepare_report_award(
        db, user,
        report_id=report_id,
        spot_content_id=report.spot_content_id,
        gps_verified=is_verified,
    )

    new_report = Report(
        id=report_id,
        user_id=user_id,
        spot_content_id=report.spot_content_id,
        crowdedness_level=report.crowdedness_level,
        waiting_time=report.waiting_time,
        parking_status=report.parking_status,
        comment=report.comment,
        photo_url=report.photo_url,
        gps_verified=is_verified,
        client_request_id=report.client_request_id,
    )
    db.add(new_report)
    if award.ledger is not None:
        # 기존 commit "앞"에 add — 별도 commit을 만들면 제보만 저장되고 크레딧은 사라지는
        # (또는 그 반대의) 상태가 실제로 생긴다.
        db.add(award.ledger)
    try:
        await db.commit()
    except IntegrityError:
        # 동시에 같은 client_request_id로 두 번 요청이 들어온 경우 (DB 유니크 제약이 최종 방어선)
        # 이 경로에서는 rollback으로 ledger도 함께 버려졌으므로 실제 적립은 0이다.
        # 위 사전조회 경로와 같은 이유로 ALREADY_AWARDED를 싣는다(C11).
        await db.rollback()
        existing = await db.scalar(select(Report).where(Report.client_request_id == report.client_request_id))
        if existing is not None:
            return _to_response(existing, nickname, credit_skip_reason="ALREADY_AWARDED")
        raise
    await db.refresh(new_report)
    return _to_response(
        new_report,
        nickname,
        credit_earned=award.earned,
        credit_skip_reason=award.skip_reason,
    )


@router.get("", response_model=List[ReportResponse])
async def get_reports(spot_content_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Report, User.nickname)
        .join(User, Report.user_id == User.id)
        .where(Report.spot_content_id == spot_content_id)
        .order_by(Report.created_at.desc())
    )
    return [_to_response(report, nickname) for report, nickname in result.all()]


@router.get("/me", response_model=List[MyReportEntry])
async def get_my_reports(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """마이 화면 "내 제보" 목록(기능 12). 스팟별 조회(`GET /reports`)와 달리 날짜 필터가
    없다 — 개인 활동 이력이라 지난 제보도 계속 보여야 한다."""
    result = await db.execute(
        select(Report).where(Report.user_id == user_id).order_by(Report.created_at.desc())
    )
    reports = result.scalars().all()
    names = await resolve_spot_names({r.spot_content_id for r in reports})
    return [
        MyReportEntry(
            id=r.id,
            spot_content_id=r.spot_content_id,
            spot_name=names.get(r.spot_content_id),
            crowdedness_level=r.crowdedness_level,
            waiting_time=r.waiting_time,
            parking_status=r.parking_status,
            comment=r.comment,
            gps_verified=r.gps_verified,
            created_at=r.created_at,
        )
        for r in reports
    ]


@router.post("/verify-location", response_model=VerifyLocationResponse)
async def verify_location(
    payload: VerifyLocationRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """기능 4(능동적 현장 인증) + 기능 6(현장 사용자 신호). 자동 알림 설정과 무관하게,
    사용자가 상세페이지에서 직접 고른 content_id 기준으로만 거리를 검증한다
    (GPS만으로 임의 관광지를 골라잡지 않음 — 좌표로 관광지를 추정하면 밀집 지역에서
    엉뚱한 곳에 인원이 쌓인다).

    기능 6이 여기에 얹혀 있다: 이 호출은 이미 "지금 내가 여기 있다"는 뜻이고 상세페이지
    진입 시 1회 + Live 화면 GPS 토글 중 3분마다 도는 채널이라, 새 위치 전송 엔드포인트를
    만들지 않고 반경 판정을 통과한 신호로 presence를 갱신한다. 좌표는 저장하지 않는다 —
    거리(distance_m)만 남긴다.
    """
    spot = await tour_service.get_spot_detail(payload.content_id)
    if not spot:
        raise HTTPException(status_code=404, detail="관광지를 찾을 수 없습니다.")

    spot_lat = float(spot.get("mapy", 0))
    spot_lng = float(spot.get("mapx", 0))
    distance = calculate_distance_m(payload.lat, payload.lng, spot_lat, spot_lng)

    # 제보 저장 시 판정과 동일한 기준(반경 + GPS 오차 허용)을 사용해, "인증 성공"인데
    # 정작 제보 제출은 거부되는 모순이 생기지 않게 한다.
    threshold = settings.GPS_VERIFICATION_RADIUS_M + settings.GPS_ERROR_MARGIN_M
    within_range = distance <= threshold
    verified = within_range or settings.DEMO_BYPASS_GPS

    if within_range:
        message = "현장 인증에 성공했습니다."
    elif settings.DEMO_BYPASS_GPS:
        message = "데모 모드로 인증되었습니다 (GPS 우회, 실제 거리 기준 미충족)."
    else:
        message = f"현재 위치에서 {int(distance)}m 떨어져 있어요. 관광지 반경 {threshold}m 이내에서만 인증할 수 있습니다."

    # 현장 사용자 기록(기능 6). 반경 밖이면 저장하지 않되 403이 아니라 200 +
    # presence_registered=false로 표현한다 — 위치 신호는 사용자의 명시적 쓰기 행동이
    # 아니라 배경 동작이라, 에러를 던지면 앱이 정상 상황을 실패로 표시한다.
    # DEMO_BYPASS_GPS가 켜져 있으면 제보·답변과 동일하게 반경 밖이어도 기록한다.
    presence_registered = False
    pending_questions: List[QuestionResponse] = []
    if verified:
        await presence_service.record_presence(
            db,
            user_id=user_id,
            spot_content_id=payload.content_id,
            distance_m=distance,
        )
        presence_registered = True
        # 답변 대기 질문 동봉: 현장 인증된 사용자만 답변할 수 있으므로, 인증에 실패한
        # 응답에 질문을 실어봐야 답할 수 없는 목록을 보여주는 셈이 된다.
        pending_questions = await fetch_pending_questions(
            db, payload.content_id, settings.PRESENCE_PENDING_QUESTION_LIMIT
        )

    return VerifyLocationResponse(
        verified=verified,
        distance_m=distance,
        threshold_m=threshold,
        message=message,
        presence_registered=presence_registered,
        pending_questions=pending_questions,
    )
