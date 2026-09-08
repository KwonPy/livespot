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
    verified: bool
    distance_m: float
    threshold_m: int
    message: str


# ──────────────────── 관광지별 자동 제보 유도 알림 설정 ────────────────────

class NotificationSettingUpsert(BaseModel):
    content_id: str
    push_enabled: bool


class NotificationSettingResponse(BaseModel):
    content_id: str
    push_enabled: bool


# ──────────────────── LIVE 상태창 (기능 5) ────────────────────
# 실제 제보(reports) 기반으로 매번 실시간 계산한다. presence/questions가 아직 없어서
# "현장 인원"·"질문"은 내려주지 않는다 — 없는 데이터를 지어내지 않는다는 원칙.

class LiveStatusResponse(BaseModel):
    content_id: str
    is_live: bool  # 최근 LIVE_WINDOW_HOURS 안에 제보가 하나라도 있는지
    recent_report_count: int  # 그 시간창 안의 제보 건수
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
