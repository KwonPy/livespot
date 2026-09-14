from pydantic import BaseModel, Field, ConfigDict
from typing import List, Literal, Optional
from datetime import datetime


# ──────────────────── API 요청 모델 ────────────────────

class NearbyRequest(BaseModel):
    lat: float
    lng: float
    radius: int = 5000

# ──────────────────── 관광지 기본/상세 모델 ────────────────────

class SpotBase(BaseModel):
    content_id: str
    content_type_id: Optional[str] = None
    title: str
    address: str
    image_url: Optional[str] = None
    mapx: float
    mapy: float
    dist: Optional[float] = None  # 거리 (미터), nearby 검색 시에만 포함


class SpotDetail(SpotBase):
    overview: Optional[str] = None
    homepage: Optional[str] = None
    tel: Optional[str] = None


class SpotIntro(BaseModel):
    """소개정보 (detailIntro2) - 콘텐트타입에 따라 필드가 다름"""
    content_id: str
    content_type_id: Optional[str] = None
    # 관광지 (12)
    use_time: Optional[str] = None        # 이용시간
    rest_date: Optional[str] = None       # 쉬는날
    exp_guide: Optional[str] = None       # 체험안내
    parking: Optional[str] = None         # 주차시설
    charge_info: Optional[str] = None     # 이용요금
    # 문화시설 (14)
    use_fee: Optional[str] = None         # 이용요금
    spend_time: Optional[str] = None      # 관람소요시간
    # 축제/행사 (15)
    event_start_date: Optional[str] = None
    event_end_date: Optional[str] = None
    event_place: Optional[str] = None
    program: Optional[str] = None


# ──────────────────── 집중률 모델 ────────────────────

class CongestionInfo(BaseModel):
    """관광지별 집중률 예측 정보 (TatsCnctrRateService)"""
    content_id: Optional[str] = None
    # 집중률 데이터셋에서 실제로 매칭된 관광지명. TourAPI의 title과 다를 수 있어
    # ('덕수궁 대한문' -> '덕수궁'), 다르면 앱이 "OO 기준"이라고 밝힌다.
    spot_name: Optional[str] = None
    base_ymd: Optional[str] = None          # 기준일 (YYYYMMDD)
    congestion_rate: Optional[float] = None  # 집중률 수치
    level: str = "unknown"                   # green / yellow / red / unknown
    description: str = "정보 없음"


class CongestionBatchItem(BaseModel):
    """지도에 떠 있는 관광지 하나. 집중률 API는 content_id를 모르고 관광지명으로만
    데이터를 구분하므로, 이름 매칭에 필요한 title과 시군구 판별에 쓸 address를 함께 받는다."""
    content_id: str
    title: str
    address: Optional[str] = None


class CongestionBatchRequest(BaseModel):
    spots: List[CongestionBatchItem] = Field(default_factory=list, max_length=100)


# ──────────────────── 사진 갤러리 모델 ────────────────────

class PhotoItem(BaseModel):
    """관광사진 갤러리 아이템 (PhotoGalleryService1)"""
    gallery_url: Optional[str] = None         # 원본 이미지 URL
    photo_title: Optional[str] = None         # 사진 제목
    photographer: Optional[str] = None        # 촬영자
    search_keyword: Optional[str] = None      # 검색 키워드


# ──────────────────── 날씨 / 혼잡도 모델 (기존 유지) ────────────────────

class WeatherInfo(BaseModel):
    """Open-Meteo 현재 날씨. 조회 실패 시에도 available=False로 채워서 200으로 내려간다.

    temp/description 필드명은 gemini.py가 참조하므로 바꾸지 않는다(하위호환).
    humidity는 Open-Meteo 연동 범위에 없어 항상 None이지만, 기존 호출자를 깨지 않도록 남긴다.
    """
    temp: Optional[float] = None          # 섭씨. 조회 실패 시 null
    description: str                      # 한국어 상태 문구. 실패 시 "정보 없음"
    humidity: Optional[int] = None        # 미사용(항상 null)
    weather_code: Optional[int] = None    # WMO 4677 원본 코드. 실패 시 null
    icon: str = "unknown"                 # 앱 아이콘 분기용 안정 키
    available: bool = True                # False면 조회 실패 (앱은 fallback 표시)


class CrowdednessInfo(BaseModel):
    level: str  # "green", "yellow", "red"
    description: str


# ──────────────────── AI 브리핑 모델 (기능 10) ────────────────────
# 정책: 본문 1필드(summary_line 없음). 관광지가 없을 때(404)를 제외하면 항상 200이며,
# AI 실패·타임아웃·키 오류에도 템플릿 문장으로 200을 반환한다. 예외 메시지는 절대 담지 않는다.

BriefingSource = Literal["AI", "CACHED_AI", "TEMPLATE", "NONE"]


class BriefingBasedOn(BaseModel):
    """이 브리핑이 실제로 어떤 재료를 보고 쓰였는지. 앱이 근거를 밝히고, 문장이 왜
    이런 내용인지 디버깅할 수 있게 하기 위한 필드다(정직성 원칙)."""
    has_report: bool      # 당일(KST) 현장 제보가 1건 이상 있었는지 — 실측
    has_congestion: bool  # 한국관광공사 방문 집중률 예측값이 있었는지 — 예측
    has_weather: bool     # 현재 날씨 조회에 성공했는지


class BriefingResponse(BaseModel):
    content_id: str
    full_briefing: str  # 3~4문장. source="NONE"일 때는 제보 유도 안내문
    # 앱은 AI / CACHED_AI 일 때만 "Gemini로 생성됨" 라벨을 렌더한다.
    # TEMPLATE·NONE에 AI 라벨을 붙이는 것을 금지한다.
    source: BriefingSource
    generated_at: datetime  # naive UTC (프로젝트 전역 규약). 캐시 히트면 원래 생성 시각
    based_on: BriefingBasedOn


# ──────────────────── 제보 / 리뷰 모델 ────────────────────

class ReviewCreate(BaseModel):
    spot_id: str
    content: str
    rating: int = Field(ge=1, le=5)
    lat: float
    lng: float


class ReviewResponse(BaseModel):
    id: str
    spot_id: str
    content: str
    rating: int
    gps_verified: bool
    created_at: datetime


CrowdednessLevel = Literal["EASY", "NORMAL", "BUSY"]
WaitingTime = Literal["NONE", "UNDER_10", "10_TO_30", "OVER_30"]
ParkingStatus = Literal["EASY", "NORMAL", "FULL"]


class ReportCreate(BaseModel):
    spot_content_id: str
    crowdedness_level: CrowdednessLevel
    waiting_time: WaitingTime
    parking_status: Optional[ParkingStatus] = None
    comment: Optional[str] = Field(default=None, max_length=30)
    photo_url: Optional[str] = None  # 선택 사진. 업로드 파이프라인은 이번 MVP 범위 밖 — 컬럼/필드만 마련.
    lat: float
    lng: float
    # 제보 창을 열 때 클라이언트가 발급하는 고유번호. 같은 값으로 재제출되면
    # 새로 만들지 않고 기존 제보를 그대로 돌려준다 (중복 제출 방지).
    client_request_id: str = Field(min_length=1, max_length=64)


class ReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    user_nickname: str  # users.nickname 조인 결과 (저장값 아님, 조회 시 계산)
    spot_content_id: str
    crowdedness_level: str
    waiting_time: str
    parking_status: Optional[str] = None
    comment: Optional[str] = None
    photo_url: Optional[str] = None
    gps_verified: bool
    created_at: datetime


# ──────────────────── GPS 능동 인증 (기능 4) ────────────────────

class VerifyLocationRequest(BaseModel):
    content_id: str
    lat: float
    lng: float


class VerifyLocationResponse(BaseModel):
    """GPS 능동 인증 응답. 기능 6(현장 사용자 수 집계)이 이 API에 얹혀 있어 필드가 둘 늘었다.

    이 호출은 이미 (ⓐ 상세페이지 진입/현장 제보 버튼, ⓑ Live 화면 GPS 토글이 켜진 동안
    3분마다) 도는 "지금 내가 여기 있다" 신호라, 새 위치 전송 채널을 만들지 않고 여기에
    presence 갱신을 얹었다. 인증이 실패해도 200이므로 앱은 아래 두 필드를 항상 읽을 수 있다.
    """

    verified: bool
    distance_m: float
    threshold_m: int
    message: str
    # 이 신호로 현장 사용자(presence) 기록이 실제로 갱신됐는지. 반경 밖이면 false지만
    # HTTP 상태는 그대로 200이다 — 위치 신호는 배경 동작이라 에러로 표시하면 안 된다.
    presence_registered: bool = False
    # 지금 이 관광지에서 답변을 기다리는 질문 상위 N건(활성·답변 0건, 최신순).
    # 웹에는 푸시가 없어 이 동봉 목록이 사실상 답변 유도의 주 전달 경로다.
    # 인증 실패(반경 밖)면 빈 배열 — 답변은 현장 인증자만 달 수 있으므로 유도할 이유가 없다.
    pending_questions: List["QuestionResponse"] = Field(default_factory=list)


# ──────────────────── 관광지별 자동 제보 유도 알림 설정 ────────────────────

class NotificationSettingUpsert(BaseModel):
    content_id: str
    push_enabled: bool


class NotificationSettingResponse(BaseModel):
    content_id: str
    push_enabled: bool


# ──────────────────── 질문/답변 알림 (기능 8) ────────────────────
# 위 spot_notification_settings(관광지별, 기능 3)와는 **완전히 별개**다. 기능 8 알림에는
# 2026-09-13부터 **on/off 설정이 전혀 없다**(015 N1·N2) — 항상 간다.
#
# 만료는 상태 컬럼이 아니라 조회 시점 계산이고, **기준은 알림이 아니라 연결된 질문**이다
# (P24, 2026-09-10 방향 수정). 알림 전용 TTL(NOTIFICATION_TTL_MINUTES=30)은 폐기됐다.
# 이제 목록·unread_count에서 빠지는 조건은 "그 질문의 created_at + 2시간(QUESTION_TTL_HOURS)이
# 지났는가" 하나뿐이다. expires_at을 함께 내려보내 앱이 서버와 같은 기준으로 남은 시간을
# 그릴 수 있게 한다. 읽음(read_at)은 이 유효시간과 무관하게 별도로 관리된다.

# 두 값 모두 실제로 응답에 실린다(015 2-2절 정정). 2026-09-13 오전 한때 NEW_QUESTION 생성이
# 중단되고 `active_join()`이 타입 필터로 걸러냈지만, 같은 날 되돌렸다 — 그 필터가 실시간
# 모달의 데이터 소스이기도 했다. 앱은 두 분기를 모두 그린다.
NotificationType = Literal["NEW_QUESTION", "NEW_ANSWER"]


class NotificationEntry(BaseModel):
    """GET /api/notifications 한 줄. type은 두 종류 모두 내려간다(015 2-2절 Q1=D).

    - NEW_ANSWER: 내가 올린 질문에 답변이 달림 → 답변 확인하러 가기
    - NEW_QUESTION: 내가 최근 30분 안에 GPS 인증한 관광지에 새 질문이 올라옴 → 답변하러 가기
      (수신자는 질문자 본인이 아니므로 "내가 쓴 질문" 탭에는 나타나지 않는다. 이 항목이
      쓰이는 곳은 실시간 모달과 미읽음 배지이지, 사용자에게 보여주는 목록 페이지가 아니다 —
      그 페이지는 015에서 없앤 채로 둔다.)

    question_id가 항상 채워지므로 앱은 탭 시 해당 질문으로 이동하면 된다. 이 값은 "내가
    쓴 질문" 목록에 안읽음 표시를 얹을 때의 매칭 키이기도 하다 — `is_read`와 함께 쓴다.
    (Optional로 둔 것은 향후 질문과 무관한 알림 종류가 생길 여지 때문이고,
    현재 구현에서 null이 되는 경로는 없다.)
    """

    model_config = ConfigDict(from_attributes=True)

    id: str
    type: NotificationType
    spot_content_id: str
    # TourAPI에서 조회한 관광지 이름. 조회 실패·삭제 시 null (알림 자체는 목록에서 빠지지 않는다).
    spot_name: Optional[str] = None
    question_id: Optional[str] = None
    body: str  # 서버가 코드 상수로 조립한 표시 문구. 앱은 그대로 그린다.
    created_at: datetime  # naive UTC
    # **연결된 질문의 created_at + 2시간**이다(알림 자신의 created_at 기준이 아니다).
    # 이 시각이 지나면 목록에서 사라진다.
    expires_at: datetime
    read_at: Optional[datetime] = None  # 아직 안 읽었으면 null
    is_read: bool  # read_at is not None 과 동치. 앱이 null 체크를 안 해도 되게 함께 내려준다


class NotificationListResponse(BaseModel):
    """GET /api/notifications. **연결된 질문이 아직 2시간 유효한** 알림만 담는다(P24).

    unread_count도 같은 기준이다 — 배지 숫자와 목록 길이가 어긋나면 "안 읽은 알림 3건"인데
    목록이 비어 있는 상태가 된다.

    `ttl_minutes` 필드는 2026-09-10 방향 수정으로 **삭제됐다.** 알림에 고정 TTL이 없어져
    내려보낼 값 자체가 없다 — 남은 시간은 항목별 `expires_at`으로만 알 수 있다.
    """

    items: List[NotificationEntry] = Field(default_factory=list)
    unread_count: int


class NotificationReadResponse(BaseModel):
    """POST /api/notifications/{id}/read · POST /api/notifications/read-all 공통 응답.

    멱등이다 — 이미 읽은 알림을 다시 읽음 처리해도 200이고 updated_count만 0이 된다.
    """

    updated_count: int  # 이번 호출로 실제 read_at이 채워진 건수
    unread_count: int  # 처리 후 남은 미읽음 수(만료 제외). 앱이 배지를 바로 갱신할 수 있게


# `PushSettingsResponse` / `PushSettingsUpdate`(기능 8 전역 알림 스위치)는 **2026-09-13에
# 삭제됐다**(015 N1·N2). 엔드포인트 `GET/POST /api/notifications/push-settings`,
# 서비스 함수 `get/set_push_enabled`, 모델 `UserNotificationSetting`, 테이블
# `user_notification_settings`(드롭 마이그레이션 `b7f3c1e9a204`), Dart의 `PushSettings`까지
# 한 세트로 제거했다. 알림은 이제 설정 없이 항상 간다.
#
# 바로 위의 `NotificationSettingUpsert`/`NotificationSettingResponse`는 **기능 3의
# 관광지별 제보 유도 알림**이라 이름이 비슷할 뿐 별개다 — 그건 살아 있다.


# ──────────────────── LIVE 상태창 (기능 5 · 6) ────────────────────
# 실제 제보(reports)·현장 신호(presences) 기반으로 매번 실시간 계산한다. 서로 다른 세 개의
# 시간창이 한 응답에 들어 있으므로(최근 2시간 / 당일 KST / 최근 30분) 앱은 각 숫자 옆에
# 근거 기간을 개별 표기해야 한다 — 한 줄에 나란히 두고 하나의 기준으로 설명하면 거짓말이 된다.

class LiveStatusResponse(BaseModel):
    content_id: str
    is_live: bool  # 최근 LIVE_WINDOW_HOURS 안에 제보가 하나라도 있는지
    recent_report_count: int  # 그 시간창 안의 제보 건수
    # 최근 PRESENCE_WINDOW_MINUTES(30분) 안에 위치 신호를 보낸 사용자 수(중복 제거).
    # Optional이 아니라 int다 — 우리 DB 조회라 실패하면 500이 정직하고, "0명"과 "모름"을
    # 구분할 필요가 없다. 외부 API용 available:false 폴백 패턴을 여기 쓰지 않는다.
    onsite_user_count: int = 0
    # 아래 3개는 "당일(KST 자정 기준)" 제보 중 가장 최근 1건의 값 — 신선도가 중요해 별도 기준 사용.
    # 당일 제보가 없으면 전부 null (어제 값을 그대로 보여주지 않음).
    current_crowdedness: Optional[str] = None
    current_waiting_time: Optional[str] = None
    current_parking_status: Optional[str] = None
    last_report_at: Optional[datetime] = None  # 당일 가장 최근 제보 시각


HotspotBasis = Literal["REPORT", "CONGESTION"]


class HotspotEntry(BaseModel):
    """HOT SPOTS 한 줄. basis="REPORT"면 실제 현장 제보 기반(1순위), basis="CONGESTION"이면
    실제 제보가 없어 한국관광공사 집중률 예측으로 대체된 항목(2순위)이다. display_level은
    두 소스를 한 화면에서 정렬·배색할 수 있도록 통일한 3단계(EASY/NORMAL/BUSY)이며, 문구는
    출처에 따라 앱이 다르게 표시한다(제보="여유/보통/혼잡", 집중률="여유/보통/높음" — 기능 9)."""

    content_id: str
    spot_title: str
    spot_address: Optional[str] = None
    # 카드 대표이미지. TourAPI firstimage 원본 URL 그대로 내려준다 — 이 CDN은 CORS 헤더가
    # 없어 Flutter Web에서 직접 로드하면 실패하므로, 앱이 /api/images/proxy로 감싸 쓴다.
    # 이미지가 없는 관광지·조회 실패 시 null(항목 자체는 목록에서 빠지지 않는다).
    spot_image_url: Optional[str] = None
    basis: HotspotBasis
    display_level: str  # EASY / NORMAL / BUSY
    report_count: Optional[int] = None  # basis=REPORT일 때만
    last_report_at: Optional[datetime] = None  # basis=REPORT일 때만
    congestion_rate: Optional[float] = None  # basis=CONGESTION일 때만


# ──────────────────── 현장 Q&A (기능 7) ────────────────────
# 정책: 질문은 자유 텍스트, 상세페이지에서만 작성(위치 제한 없음), 등록 즉시 ACTIVE,
# 2시간 뒤 EXPIRED(만료돼도 조회는 가능, 새 답변만 불가). 답변은 GPS 현장 인증된
# 사용자만, 상세페이지·Live 페이지 양쪽에서, 복수 답변 허용, 수정/삭제 없음.

QuestionStatus = Literal["ACTIVE", "EXPIRED"]


class QuestionCreate(BaseModel):
    spot_content_id: str
    content: str = Field(min_length=1, max_length=200)


class AnswerCreate(BaseModel):
    content: str = Field(min_length=1, max_length=200)
    lat: float
    lng: float


class AnswerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    question_id: str
    user_id: str
    user_nickname: str  # users.nickname 조인 결과
    content: str
    created_at: datetime


class QuestionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    user_nickname: str
    spot_content_id: str
    content: str
    status: QuestionStatus  # created_at + 2시간 기준으로 매 조회 시점에 계산 (저장값 아님)
    answer_count: int
    created_at: datetime
    expires_at: datetime
    answers: List[AnswerResponse] = Field(default_factory=list)


# VerifyLocationResponse가 QuestionResponse를 앞에서 문자열로 참조하고 있어(위치 신호
# 응답에 답변 대기 질문을 동봉 — 기능 6) 여기서 전방 참조를 해소한다. 이 줄이 없으면
# FastAPI가 응답 스키마를 만들 때 전방 참조 미해소로 죽을 수 있다.
VerifyLocationResponse.model_rebuild()


# ──────────────────── Credit + 뱃지 (기능 4 · 11) ────────────────────
# 적립 트리거는 제보(+10)·답변(+5) 두 곳뿐이고, 질문은 0점이라 원장 행조차 만들지 않는다.
# 뱃지는 저장하지 않는다 — 누적 크레딧(양수 원장 합계)에서 매 조회 시점에 계산한다
# (function.md 기능 11 "별도 테이블 없이 credit_ledger 합계에서 계산").
# 등급 컷·라벨·이모지를 전부 서버가 내려보내는 이유: 앱이 숫자를 보고 등급을 판정하면
# 등급표가 양쪽에 복제되어 서버에서 컷을 바꿔도 앱이 옛 기준으로 그린다.

CreditReason = Literal["REPORT", "ANSWER"]


class CreditBadge(BaseModel):
    """뱃지 1개. next_* 3개는 최상위 등급(마스터)에서만 null이 된다 —
    "다음 등급까지 N점" 진행바를 그릴 수 없는 유일한 경우라서, 앱은 이 셋의 null을
    "더 오를 곳이 없음"으로 읽으면 된다."""

    code: str  # SPROUT / VISITOR / EXPLORER / VETERAN / MASTER
    label: str  # 새싹 / Spot 탐방객 / ...
    emoji: str
    min_credit: int  # 이 등급의 하한 (앱이 진행바 시작점으로 씀)
    next_label: Optional[str] = None  # 최상위 등급이면 null
    next_at: Optional[int] = None  # 다음 등급의 하한. 최상위면 null
    remaining: Optional[int] = None  # 다음 등급까지 남은 크레딧. 최상위면 null


class CreditSummaryResponse(BaseModel):
    """GET /api/credits/me. 사용자도 원장도 없으면 에러가 아니라 0 + 최하위 뱃지를 돌려준다."""

    user_id: str
    nickname: str
    balance: int  # users.credit_balance 캐시 = 현재 쓸 수 있는 잔액
    total_earned: int  # 원장의 양수 합계 = 누적 획득. 뱃지 판정 기준은 이쪽이다
    badge: CreditBadge


class CreditLedgerEntry(BaseModel):
    """GET /api/credits/me/ledger의 한 행. 회수(음수)도 삭제가 아니라 행으로 남기므로
    amount는 음수일 수 있다."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    amount: int
    reason: str  # REPORT / ANSWER
    source_type: str  # report / answer
    source_id: str  # 제보 id 또는 질문 id(답변 적립은 질문당 1회라 question_id)
    created_at: datetime


class ActivityCountResponse(BaseModel):
    """GET /api/credits/me/activity. 마이 화면 스탯 행의 실제 값 — 적립 여부와 무관한
    '내가 쓴 글'의 총 건수다(상한 초과나 GPS 미인증으로 적립되지 않은 것도 포함)."""

    report_count: int
    answer_count: int
    question_count: int


# ──────────────────── MyPage 활동 목록 (기능 12) ────────────────────
# "내 제보"·"내 Q&A"는 spot_content_id만으론 화면에 관광지 이름을 못 보여준다.
# 이 3개 응답에 한해 spot_name을 조인해서 내려준다(services/spot_lookup.py).
# 관광지 조회가 실패하면(삭제·일시 장애) spot_name은 null — 앱은 그 경우 폴백 문구를 그린다.
# "나"의 목록이라 user_id·user_nickname은 넣지 않는다(항상 본인이라 의미가 없다).


class MyReportEntry(BaseModel):
    """GET /api/reports/me 한 줄. 시간 순서만 다를 뿐 [ReportResponse]와 같은 제보 데이터다."""

    id: str
    spot_content_id: str
    spot_name: Optional[str] = None
    crowdedness_level: str
    waiting_time: str
    parking_status: Optional[str] = None
    comment: Optional[str] = None
    gps_verified: bool
    created_at: datetime


class MyQuestionEntry(BaseModel):
    """GET /api/questions/me 한 줄. 스팟별 Q&A 목록과 달리 "오늘(KST)"로 거르지 않는다 —
    내 활동 이력이므로 지난 질문도 계속 보여야 한다."""

    id: str
    spot_content_id: str
    spot_name: Optional[str] = None
    content: str
    status: QuestionStatus
    answer_count: int
    created_at: datetime
    expires_at: datetime
    answers: List[AnswerResponse] = Field(default_factory=list)


class MyAnswerEntry(BaseModel):
    """GET /api/questions/me/answers 한 줄. 내 답변만으로는 무슨 질문에 단 것인지 알 수
    없으므로 원 질문 내용(question_content)을 함께 조인해 내려준다."""

    id: str
    question_id: str
    spot_content_id: str
    spot_name: Optional[str] = None
    question_content: str
    content: str
    created_at: datetime


# ──────────────────── 북마크 (기능 12) ────────────────────
# 관광지는 로컬 테이블이 없으므로(설계 원칙 2) content_id 문자열로만 참조한다.
# 목록 응답의 spot_* 3개는 서버가 TourAPI에서 조인한 값이고, 조회 실패 시 null이다
# (항목이 목록에서 빠지지는 않는다 — 앱이 폴백 문구를 그린다).


class BookmarkCreate(BaseModel):
    """POST /api/bookmarks 요청 본문."""

    content_id: str


class BookmarkToggleResponse(BaseModel):
    """POST/DELETE /api/bookmarks 공통 응답. 두 동작 모두 멱등이라 이미 그 상태여도
    409/404가 아니라 200 + 최종 상태를 돌려준다."""

    content_id: str
    bookmarked: bool


class BookmarkEntry(BaseModel):
    """GET /api/bookmarks 한 줄. 목록 카드가 제목·주소·대표이미지를 함께 그리므로
    [MyReportEntry]와 달리 spot_address·spot_image_url까지 조인한다."""

    content_id: str
    spot_name: Optional[str] = None
    spot_address: Optional[str] = None
    spot_image_url: Optional[str] = None
    created_at: datetime


# ──────────────────── 카카오 로그인 (기능 9) ────────────────────
# 인증 방식: 카카오 JS SDK 팝업(Q1-B) → 프론트가 얻은 **카카오 access token**을 서버로 POST
# → 서버가 kapi.kakao.com에 검증(P6) → **우리 자체 JWT**를 발급(Q2-A).
# 카카오 ID는 응답에 절대 싣지 않는다(P4) — 클라이언트가 보는 식별자는 내부 UUID뿐이다.


class KakaoLoginRequest(BaseModel):
    """POST /api/auth/kakao 요청 본문.

    이 토큰은 **카카오가 발급한 것**이고, 우리 API의 인증 수단이 아니다.
    서버가 검증한 뒤 버리며, 우리 DB에 저장하지 않는다(저장하면 유출 시 카카오
    사용자 정보까지 함께 새는 자산이 된다. 우리는 이 토큰으로 할 일이 로그인 시점의
    본인 확인 한 번뿐이라 보관할 이유가 없다).
    """

    kakao_access_token: str


class AuthUser(BaseModel):
    """로그인한 사용자 1명. POST /api/auth/kakao 응답의 `user`,
    GET /api/auth/me, PUT /api/auth/me/nickname 응답이 **전부 같은 모양**이다 —
    앱이 모델 하나(AuthUser)만 만들면 된다.

    `user_id`는 내부 UUID(P8)다. 카카오 회원번호가 아니다.

    **2026-09-14: P22 폐기.** `nickname`은 이제 **사용자가 앱에서 직접 입력한 값**이고
    **unique**하다(P23·P24). 카카오가 준 닉네임을 저장하지 않으며, 아직 정하지 않았으면
    `null`이다(P25 — 미설정 상태의 유일한 표현은 `nickname IS NULL`이다).
    다만 unique는 **표시 계층의 제약**일 뿐 식별 키는 여전히 `users.id`뿐이다(P24).

    `nickname_required`는 `nickname is None`과 같은 값이지만, **앱이 null을 직접 해석해
    정책을 추론하지 않도록** 서버가 계산해 실어 준다(P26). 계산 지점은
    `auth.py::_to_auth_user()` **한 곳뿐**이다.
    `is_new_user`(LoginResponse)와는 **다른 값이다**(P27) — 기존 사용자도 미설정일 수 있다.

    `profile_image_url`은 **항상 null이 된다**(P39·P40). 카카오 동의항목을 하나도 받지
    않기로 확정돼 채울 값이 없다. 그래도 필드를 남기는 이유는, 앱 자체 프로필 이미지
    업로드가 붙을 때 이 자리가 그대로 쓰이기 때문이다(스키마·Dart 모델을 다시 흔들지 않는다).
    """

    user_id: str
    nickname: Optional[str] = None            # 미설정이면 null (P25)
    nickname_required: bool                   # nickname is None (P26). 앱은 이것만 본다
    profile_image_url: Optional[str] = None   # 앞으로 항상 null (P40)
    credit_balance: int
    trust_level: str
    created_at: datetime                      # naive UTC (가입 시각)


class NicknameUpdateRequest(BaseModel):
    """PUT /api/auth/me/nickname 요청 본문.

    **검증도 정규화도 서버가 한다**(P30). 여기에 pattern/min_length를 걸지 않는 이유:
    Pydantic이 막으면 422 + 리스트 형식 detail이 되는데, 2-4절이 **400 + 한국어 문자열**로
    확정했다. 화면에 그대로 띄울 수 있는 문구를 서버가 고르기 위해 검증을 라우터
    (services/nickname.py)로 내린다.
    """

    nickname: str


class NicknameAvailability(BaseModel):
    """GET /api/auth/nickname-available?nickname=... 응답 (Q2-B).

    **이 응답은 조언일 뿐 확정이 아니다.** 확인과 제출 사이에 남이 선점할 수 있으므로
    최종 판정은 언제나 PUT 시점의 409다. 앱은 이 값으로 입력창 아래 문구만 그린다.

    `nickname`은 **서버가 정규화한 결과**(strip + NFC)를 돌려준다 — 앱이 보낸 것과 다를 수
    있고, 실제로 저장·비교되는 값이 이쪽이다.
    `reason`은 `available=true`면 null, false면 화면에 그대로 띄울 한국어 문구다.
    """

    nickname: str
    available: bool
    reason: Optional[str] = None


class LoginResponse(BaseModel):
    """POST /api/auth/kakao 응답.

    `expires_at`을 함께 주는 이유: 앱이 토큰을 shared_preferences에 저장했다가
    복원할 때(P19), 만료가 뻔한 토큰으로 요청을 쏘고 401을 받는 대신 미리 걸러낼 수
    있게 하기 위함이다. 다만 **판정의 진실은 서버에 있다** — 앱은 이 값을 힌트로만 쓴다.

    `is_new_user`는 이번 요청에서 users 행이 새로 만들어졌는지다(P7의 upsert 결과).
    가입 축하 문구 같은 UI 분기에 쓰라고 주는 값이고, 권한과는 무관하다.
    """

    access_token: str
    token_type: str = "Bearer"
    expires_at: datetime                      # naive UTC
    is_new_user: bool
    user: AuthUser
