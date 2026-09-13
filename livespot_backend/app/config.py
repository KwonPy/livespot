from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator
from typing import Optional

class Settings(BaseSettings):
    TOUR_API_KEY: str
    OPENWEATHER_API_KEY: Optional[str] = ""
    GEMINI_API_KEY: Optional[str] = ""
    KAKAO_API_KEY: Optional[str] = ""
    
    # 지역 필터: "seoul" = 서울만 노출 (운영), "none" = 모든 지역 허용 (개발/테스트)
    SERVICE_AREA_FILTER: str = "none"

    # 로컬 개발 기본값은 SQLite. 배포 시 .env에서 PostgreSQL DSN(postgresql+asyncpg://...)으로 덮어씀
    # (Phase 2+ 로그인·제보·Credit 등 사용자 데이터용. TourAPI 데이터는 캐싱하지 않고 실시간 호출로 사용)
    DATABASE_URL: str = "sqlite+aiosqlite:///./livespot.db"

    # Railway 등 PaaS의 Postgres 플러그인은 DATABASE_URL을 postgres:// 또는 postgresql://
    # 스킴으로 내려준다. SQLAlchemy 비동기 엔진(asyncpg 드라이버)이 요구하는
    # postgresql+asyncpg:// 로 여기서 자동 보정한다.
    @field_validator("DATABASE_URL")
    @classmethod
    def _normalize_database_url(cls, v: str) -> str:
        if v.startswith("postgres://"):
            return "postgresql+asyncpg://" + v[len("postgres://"):]
        if v.startswith("postgresql://"):
            return "postgresql+asyncpg://" + v[len("postgresql://"):]
        return v

    # GPS 인증 (기능 3): 100m + 측정오차(최대 50m까지 인정) → 실제 판정 반경은 두 값의 합(150m)
    GPS_VERIFICATION_RADIUS_M: int = 100
    GPS_ERROR_MARGIN_M: int = 50

    # LIVE 상태창(기능 5): "지금 붐빈다"를 판정하는 기준 시간창. 이 시간 안에 제보가 없으면
    # LIVE가 아니라고 판정한다 (과거 제보로 부풀리지 않기 위함).
    LIVE_WINDOW_HOURS: int = 2

    # ── 현장 사용자 수 집계 (기능 6) ──
    # "현장 사용자" = 마지막 위치 신호(presences.last_seen)가 이 시간 안에 있는 사용자.
    # 연결 상태가 아니라 타임스탬프로 판정하므로, 앱이 꺼져 있어도 30분 안이면 집계된다.
    # 앱의 constants.dart::presenceWindowMinutes와 짝이다 — 어긋나면 앱과 서버가 서로 다른
    # 기준으로 같은 숫자를 설명하게 된다(앱 문구: "최근 30분 기준 N명").
    PRESENCE_WINDOW_MINUTES: int = 30

    # presences 행을 실제로 DELETE하는 기준(프라이버시 약속). 별도 배치를 두지 않고,
    # 위치 신호가 들어올 때마다 같은 트랜잭션에서 이 시간이 지난 행을 지운다.
    PRESENCE_RETENTION_HOURS: int = 24

    # 위치 신호 응답에 함께 실어 보내는 "답변 대기 질문"의 최대 건수. 푸시가 없는 웹에서
    # 답변을 유도하는 사실상의 주 전달 경로라 응답에 동봉하지만, 배너 하나에 들어갈 만큼만 준다.
    PRESENCE_PENDING_QUESTION_LIMIT: int = 5

    # 노트북(WiFi/유선) 데모 시연용 우회 스위치. 켜면 GPS 범위를 벗어나도 제보를 거부하지 않고
    # gps_verified=false로 저장한다. 실서비스 배포 시 반드시 False로 둘 것.
    DEMO_BYPASS_GPS: bool = False

    # ── AI 브리핑 (기능 10) ──
    # 모델명. 구 gemini-2.0-flash는 404 NOT_FOUND로 폐기됐다.
    # lite를 고른 이유는 품질이 아니라 응답 시간이다 — 실측(2026-09, 각 4~6회):
    #   gemini-3.6-flash       중앙값 26초, 5초 안에 들어온 비율 0/6  ← 사실상 매번 템플릿 폴백
    #   gemini-3.5-flash-lite  중앙값 1.1초, 4/4                      ← 채택
    # 3~4문장 요약은 lite로 충분하고, 상세페이지에서 사람이 기다리는 시간이 곧 예산이다.
    # 모델이 폐기되거나 느려지면 .env의 GEMINI_MODEL로 덮어쓴다(코드 수정 불필요).
    GEMINI_MODEL: str = "gemini-3.5-flash-lite"

    # AI 호출 상한 시간(초). 상세페이지에서 사람이 실제로 기다리는 시간이고, 앱의
    # receiveTimeout이 8초라 그보다 먼저 포기해야 앱에 타임아웃 에러가 뜨지 않는다.
    # 초과하면 예외를 던지지 않고 템플릿 문장으로 넘어간다.
    GEMINI_TIMEOUT_SECONDS: float = 5.0

    # 생성된 브리핑의 메모리 캐시 수명(초). 캐시 키에 재료 서명이 들어가므로 재료가 바뀌면
    # 이 시간과 무관하게 새로 생성된다. TTL은 "재료가 그대로여도 오전에 만든 문장을 저녁까지
    # 보여주지 않기" 위한 상한이다. DB에 저장하지 않으므로 서버 재시작 시 사라진다.
    BRIEFING_CACHE_TTL_SECONDS: int = 21600  # 6시간

    # 프롬프트에 넣을 당일 제보 코멘트 건수 상한. 코멘트는 30자 제한이라 토큰 부담은 작지만,
    # 사용자 작성 텍스트가 프롬프트로 들어가는 경로이므로 건수를 명시적으로 제한한다.
    BRIEFING_COMMENT_LIMIT: int = 3

    # 개발/QA 전용: 켜면 요청 헤더 X-Test-User-Id로 test_user/seed_user_* 중 하나를 골라
    # 그 사용자로 동작하는 척 할 수 있다 (여러 사용자의 제보 상황을 한 기기에서 재현하기 위함).
    # 실서비스 배포 시 반드시 False로 둘 것 — 켜져 있으면 누구나 헤더만으로 다른 사용자 행세를 할 수 있다.
    TEST_MODE: bool = False

    # ── Credit 적립 (기능 4) ──
    # 제보가 답변보다 비싼 이유: 제보는 현장에 실제로 가야 쓸 수 있는 이 서비스의 본체이고,
    # 답변은 텍스트 한 줄이라 하루에 여러 건 쓸 수 있다. 질문은 0점이라 상수 자체가 없다
    # (보상을 노린 무의미한 질문 반복을 막기 위해 원장 행조차 만들지 않는다).
    # 이 값을 바꾸면 이미 쌓인 원장 행과 기준이 섞이므로, 바꿀 때는 반드시 작업일지에 남길 것.
    CREDIT_AMOUNT_REPORT: int = 10
    CREDIT_AMOUNT_ANSWER: int = 5

    # 같은 장소에서 하루(KST)에 적립되는 최대 건수. 초과해도 제보·답변 자체는 정상 저장되고
    # 적립만 건너뛴다. "하루"의 정의는 services/report_window.today_cutoff_utc()를 공유한다 —
    # LIVE·브리핑·Q&A와 하루 경계가 갈리면 같은 화면이 서로 다른 기준으로 그려진다.
    CREDIT_DAILY_LIMIT_PER_SPOT: int = 3

    # ── 질문/답변 알림 (기능 8) ──
    # **알림 전용 수명 상수가 없다**(2026-09-10 방향 수정 P24). 알림이 목록에 보이는 기준은
    # "연결된 질문이 아직 유효한가"이고, 그 값은 db/models/question.py의 QUESTION_TTL_HOURS(2)
    # 하나뿐이다. 예전의 NOTIFICATION_TTL_MINUTES(30) / MAX_RECIPIENTS(10) /
    # MAX_PER_USER_PER_HOUR(2) / RATE_WINDOW_HOURS / DEDUP_HOURS(6)는 발송 제한 3종 폐기(P26)와
    # 함께 전부 삭제됐다. 여기에 같은 값을 다시 두면 질문 TTL과 갈라진다.

    # GET /notifications가 한 번에 돌려주는 최대 건수. 목록 응답 크기의 상한.
    NOTIFICATION_LIST_LIMIT: int = 50

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

settings = Settings()
