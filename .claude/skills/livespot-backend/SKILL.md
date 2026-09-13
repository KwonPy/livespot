---
name: livespot-backend
description: "LiveSpot FastAPI 백엔드에 기능을 추가·수정하는 표준 절차. Pydantic 스키마, SQLAlchemy 비동기 모델, Alembic 마이그레이션, 라우터 작성과 등록, 외부 공공 API(TourAPI/집중률/날씨/Gemini) 연동, GPS 검증, 캐싱을 다룬다. livespot_backend/ 하위를 건드리는 모든 작업 — 'API 추가', '엔드포인트 만들어', '테이블 추가', '마이그레이션', '스키마 수정', '백엔드 고쳐줘', 'DB에 저장되게', '응답에 필드 추가' — 에 반드시 이 스킬을 사용할 것. 후속 작업(응답 필드 추가, 기존 API 수정, 버그 수정)에도 동일하게 적용한다."
---

# LiveSpot 백엔드 구현 절차

계약(응답 스키마)을 먼저 못박고 그 다음에 로직을 짠다. 계약이 흔들리면 앱이 조용히 `null`로 깨진다.

## 절대 규칙 3가지

1. **응답 필드는 snake_case.** Pydantic 필드명이 그대로 JSON 키가 된다. `alias_generator`를 걸지 않는다. `function.md` 5장의 "camelCase 통일" 문장은 폐기됐다 — 전 화면의 Dart `fromJson`이 snake_case 키를 읽도록 구현돼 있다.
2. **시각은 `datetime.utcnow()` (naive UTC).** 타임존을 붙이지 않는다. Dart가 `Z`를 붙여 파싱하는 전제다.
3. **새 라우터는 `app/api/router.py`에 등록해야 끝.** 빠뜨리면 404다.

## 작업 순서

### 1단계 — 스키마 (`app/models/schemas.py`)

요청·응답 모델은 전부 이 한 파일에 모은다. 계약을 한눈에 보기 위함이다.

```python
class ThingCreate(BaseModel):
    spot_content_id: str          # 관광지는 TourAPI content_id 문자열로만 참조
    content: str
    lat: float
    lng: float

class ThingResponse(BaseModel):
    id: int
    spot_content_id: str
    user_id: str
    user_nickname: str            # 조인 결과도 평평하게 펼쳐 담는다
    content: str
    created_at: datetime          # naive UTC
    status: Literal["ACTIVE", "EXPIRED"]
    extra_count: Optional[int] = None   # 조건부 필드는 반드시 Optional
```

조건부로만 채워지는 필드(`basis=REPORT`일 때만 있는 `report_count` 등)는 **반드시 `Optional`로 선언한다.** 앱이 non-null로 캐스팅하면 예외가 난다.

**스키마를 확정한 즉시 `flutter-builder`에게 응답 shape 전문을 통지한다.** 그래야 앱 작업이 병렬로 시작된다. 이후 필드가 하나라도 바뀌면 즉시 재통지한다.

### 2단계 — DB 모델 (`app/db/models/{name}.py`)

```python
from sqlalchemy import String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from datetime import datetime
from app.db.base import Base

class Thing(Base):
    __tablename__ = "things"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String, ForeignKey("users.id"), index=True)
    spot_content_id: Mapped[str] = mapped_column(String, index=True)  # TourAPI 참조, FK 아님
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
```

`app/db/models/__init__.py`에 import를 추가한다. 빠뜨리면 Alembic autogenerate가 테이블을 못 본다.

관광지는 로컬 테이블이 없다. `spot_content_id`는 항상 **문자열 컬럼**이고 FK가 아니다.

### 3단계 — 마이그레이션

```
cd livespot_backend
./venv/Scripts/python.exe -m alembic revision --autogenerate -m "add_things_table"
./venv/Scripts/python.exe -m alembic upgrade head
```

생성된 파일을 반드시 열어 확인한다. SQLite에서는 autogenerate가 타입/제약 변경을 놓치는 경우가 있다. 기존 리비전을 수정하지 말고 항상 새로 쌓는다. `livespot.db`를 삭제하지 않는다 — 시드 데이터가 사라진다.

### 4단계 — 라우터 (`app/api/{name}.py`)

```python
router = APIRouter()

@router.post("", response_model=ThingResponse, status_code=201)
async def create_thing(
    payload: ThingCreate,
    user_id: str = Depends(get_current_user_id),   # 하드코딩 금지
    db: AsyncSession = Depends(get_db),
):
    ...
```

`router.py`에 등록:
```python
api_router.include_router(things.router, prefix="/things", tags=["things"])
```

전체 경로는 `/api` + prefix + 라우터 경로가 된다 (`main.py`가 `prefix="/api"`로 마운트).

### 5단계 — 스모크

`livespot-run` 스킬로 서버를 띄우고 curl로 **실제 응답 JSON을 본다.** Pydantic 정의를 읽은 것은 검증이 아니다.

## 자주 쓰는 패턴

### GPS 검증 (쓰기 작업의 권한 판정)

권한이 걸린 쓰기는 클라이언트의 "인증 완료" 상태를 절대 믿지 않는다. **매 요청마다 서버가 좌표를 다시 계산한다.**

```python
spot = await tour_service.get_spot_detail(payload.spot_content_id)
distance = calculate_distance_m(payload.lat, payload.lng, spot_lat, spot_lng)
threshold = settings.GPS_VERIFICATION_RADIUS_M + settings.GPS_ERROR_MARGIN_M   # 100 + 50
if distance > threshold and not settings.DEMO_BYPASS_GPS:
    raise HTTPException(400, f"현재 위치에서 {int(distance)}m 떨어져 있어요. 관광지 반경 {threshold}m 이내에서만 ...")
```

`reports.py`의 기존 구현을 참조해 동일한 문구·임계값을 쓴다. 임계값을 새로 정하지 않는다.

### TTL / 하루 단위 리셋 — 배치를 만들지 마라

만료는 별도 컬럼이나 스케줄러 없이 **조회 시점 계산**으로 구현한다. 상태 컬럼을 두면 배치가 필요해지고, 배치가 늦으면 상태가 거짓이 된다.

```python
def _status(q: Question) -> str:
    return "EXPIRED" if datetime.utcnow() >= q.created_at + timedelta(hours=TTL_HOURS) else "ACTIVE"
```

"하루 단위 리셋"도 데이터를 지우는 게 아니라 **오늘(KST) 것만 필터링**한다. `questions.py::_kst_today_start_utc()` / `live.py::_today_cutoff_utc()`를 재사용한다.

### 발송 상한·쿼터 — "무엇을 세는지"까지 정해야 명세가 끝난다

"1인당 시간당 최대 N회" 같은 상한을 구현할 때, **이벤트 종류가 둘 이상이면 어느 종류가 그 쿼터를 먹는지가 명세에 비어 있는 경우가 많다.** 그냥 구현하면 종류를 구분하지 않은 SELECT가 되고, 그 결과 **먼저 도착한 저가치 알림이 뒤에 올 고가치 알림을 밀어낸다.**

실제 사례(기능 8): 상한 2건을 `NEW_QUESTION`(광고성)과 `NEW_ANSWER`(내가 기다리던 답변)가 공유해서, 붐비는 곳에 있던 사용자가 **본인 질문의 답변 알림을 못 받았다.** 명세대로 구현했으므로 코드 버그가 아니었고, 그래서 QA에서도 "실패"가 아니라 "정책 판단 필요"로 올라왔다.

상한을 구현하기 전에 아래를 답한다. 답이 명세에 없으면 **임의로 고르지 말고 미결정으로 올린다.**

1. 세는 단위가 무엇인가 — 전체인가, 종류별인가?
2. 종류가 여럿이면 우선순위가 있는가? 있다면 낮은 것이 높은 것을 밀어내도 되는가?
3. 면제 대상이 있는가? (수신자가 항상 1명이고 사용자가 직접 유발한 결과라면 면제 후보다)

그리고 **필터를 거는 순서가 결과를 바꾼다.** 전체 상한("한 번에 최대 10명")은 **맨 마지막에** 자른다. 먼저 자르면 앞 10명이 개인별 제한에 걸렸을 때, 받을 수 있었던 뒤의 사람들이 이유 없이 누락된다.

```python
allowed = [uid for uid in onsite if uid != actor]     # 본인 제외
allowed = exclude_opted_out(allowed)                  # 전역 스위치 OFF 제외
allowed = exclude_rate_limited(allowed)               # 개인별 시간당 상한
allowed = exclude_recently_sent(allowed)              # 중복 방지
return allowed[:settings.MAX_RECIPIENTS]              # ← 전체 상한은 마지막
```

### 같은 판정을 두 곳이 쓰면 라우터가 아니라 서비스에 둔다

"이 조건에 해당하는 사용자/항목은 누구인가"를 **두 개 이상의 기능이 물어보게 될 것 같으면**, 라우터에 쿼리를 직접 쓰지 말고 `app/services/`에 판정 함수로 뺀다. 각 라우터가 자기 쿼리를 짜면 조건이 조금씩 갈려서 **"화면에는 3명이라고 떠 있는데 알림은 1명에게만 가는"** 상태가 된다. 이건 테스트로 잡히지 않는다 — 양쪽 다 각자는 맞기 때문이다.

```python
# services/presence.py — 인원 표시와 (앞으로 만들) 푸시 대상이 같은 WHERE를 쓴다
async def count_onsite_users(db, spot_content_id) -> int: ...
async def get_onsite_user_ids(db, spot_content_id) -> List[str]: ...
```

아직 두 번째 소비자가 없어도 만든다. 시간창 cutoff도 함수 안에 복붙하지 말고 `services/report_window.py` 한 곳에서 가져온다.

### 외부 API — 읽기는 살아있게

날씨·집중률·AI 브리핑이 실패해도 예외를 던지지 않는다. 폴백 값을 반환한다.

```python
try:
    data = await fetch_external(...)
except Exception:
    return CongestionInfo(level="unknown", description="정보 없음")
```

앱의 `receiveTimeout`이 8초이므로 서버는 그보다 먼저 실패를 반환해야 한다. 외부 호출에 반드시 타임아웃을 건다.

**새로 만들기 전에 `app/services/`를 먼저 읽어라.** 필요한 것이 이미 캐싱까지 돼 있는 경우가 많다:

| 파일 | 담당 |
|---|---|
| `tour_api.py` | 관광지 목록·상세·소개·주변 |
| `congestion.py` | 방문 집중률 예측 (관광지명 매칭 + 캐싱) |
| `crowdedness.py` | 제보 기반 현재 현장 상황 |
| `photo_gallery.py` `weather.py` `gemini.py` | 사진 / 날씨 / AI 브리핑 |
| `geo.py` `cache.py` `region_codes.py` | 거리 / TTL 캐시 / 시군구 코드 |

TourAPI 데이터를 DB에 캐싱하지 않는다. 속도가 필요하면 `cache.py`의 인메모리 `TTLCache`를 쓴다.

### 성격이 다른 데이터를 한 응답에 담을 때

실측(제보)과 예측(집중률)을 **하나의 값으로 합치지 않는다.** 출처를 나타내는 필드(`basis`)를 두고, 정렬도 그룹을 나눠서 한다. 앱이 "무엇에 근거한 숫자인지" 밝힐 수 있어야 한다.

### 비동기 SQLAlchemy

```python
result = await db.execute(
    select(Thing, User.nickname)
    .join(User, Thing.user_id == User.id)
    .where(Thing.spot_content_id == content_id)
    .order_by(Thing.created_at.desc())
)
rows = result.all()
await db.commit()
```

동기 ORM(`db.query(...)`)을 쓰지 않는다. 엔진이 `create_async_engine`이다.

## 새 설정값을 추가할 때

`app/config.py::Settings`에 기본값과 함께 넣고, `.env.example`도 갱신한다. 앱의 `constants.dart`와 짝이 되는 값이면 양쪽 주석에 대응 관계를 명시한다 (`LIVE_WINDOW_HOURS` ↔ `liveWindowHours`). 짝이 어긋나면 앱과 서버가 다른 기준으로 같은 화면을 그린다.
