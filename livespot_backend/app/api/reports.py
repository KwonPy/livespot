import uuid

from fastapi import APIRouter, Depends, HTTPException
from typing import List
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.db.models.report import Report
from app.db.models.user import User
from app.api.deps import get_current_user_id
from app.models.schemas import (
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
from app.services.question_query import fetch_pending_questions
from app.services.spot_lookup import resolve_spot_names

router = APIRouter()
tour_service = TourAPIService()


def _to_response(report: Report, nickname: str) -> ReportResponse:
    return ReportResponse(
        id=report.id,
        user_id=report.user_id,
        user_nickname=nickname,
        spot_content_id=report.spot_content_id,
        crowdedness_level=report.crowdedness_level,
        waiting_time=report.waiting_time,
        parking_status=report.parking_status,
        comment=report.comment,
        photo_url=report.photo_url,
        gps_verified=report.gps_verified,
        created_at=report.created_at,
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

    # 중복 제출: 같은 client_request_id로 이미 저장된 제보가 있으면 새로 만들지 않고 그대로 돌려준다.
    existing = await db.scalar(select(Report).where(Report.client_request_id == report.client_request_id))
    if existing is not None:
        return _to_response(existing, user.nickname)

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
    # 같은 장소 하루 상한 초과) ledger가 None이지만 제보 자체는 그대로 저장되고 응답도
    # 동일하다 — 크레딧을 못 받았다고 정보 제공을 막지는 않는다(P15).
    ledger = await credit_service.prepare_report_award(
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
    if ledger is not None:
        # 기존 commit "앞"에 add — 별도 commit을 만들면 제보만 저장되고 크레딧은 사라지는
        # (또는 그 반대의) 상태가 실제로 생긴다.
        db.add(ledger)
    try:
        await db.commit()
    except IntegrityError:
        # 동시에 같은 client_request_id로 두 번 요청이 들어온 경우 (DB 유니크 제약이 최종 방어선)
        await db.rollback()
        existing = await db.scalar(select(Report).where(Report.client_request_id == report.client_request_id))
        if existing is not None:
            return _to_response(existing, user.nickname)
        raise
    await db.refresh(new_report)
    return _to_response(new_report, user.nickname)


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
