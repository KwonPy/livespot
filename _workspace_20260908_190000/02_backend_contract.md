# 백엔드 계약: Credit + 뱃지 (기능 4 · 11)

> 작성: 2026-09-08 / backend-builder
> 근거: `_workspace/01_spec.md` 2절(P1~P24), 2.1.1절 확정값
> 아래 JSON은 전부 **실제 서버 curl 실측 원문**이다 (uvicorn 127.0.0.1:8000, `TEST_MODE=true`, `DEMO_BYPASS_GPS=false`).

## 0. 요약 — P21에서 벗어난 것

**없다.** 엔드포인트 3개의 경로·필드명·중첩 구조가 P21과 정확히 일치한다.
`flutter-builder`가 P21을 계약으로 삼아 작성한 코드는 그대로 맞는다.

다만 P21이 값을 정하지 않아 서버가 확정한 것 3가지 + 스펙 해석 1건이 있다. 앱 구현에 영향이 있으므로 아래에 굵게 표시한다.

1. **`badge.code`의 실제 문자열**: `SPROUT` / `VISITOR` / `EXPLORER` / `VETERAN` / `MASTER` (P21은 `code`가 있다고만 정하고 값은 안 정했다). 앱이 code로 분기한다면 이 5개다.
2. **`badge.next_label` / `next_at` / `remaining` 3개는 nullable**. 최상위 등급(`code == "MASTER"`)일 때만 셋 다 `null`이고, 그 외에는 항상 값이 있다. **non-null 캐스팅 금지** — 마스터 사용자 화면에서만 터지는 버그가 된다. 최상위에서 `0`이나 자기 자신을 넣지 않은 이유: 앱이 100% 진행바를 그려 "곧 다음 등급"으로 오해시키기 때문이다.
3. **`GET /me/ledger`의 최상위가 배열**이다. 객체로 감싸지 않았다 (P21 표기 `[ {...} ]` 그대로).
4. **`activity`의 건수는 적립 여부와 무관한 총 작성 건수**다. 아래 3.3의 주의 참조 — 앱이 이 값으로 크레딧을 역산하면 어긋난다.

공통 규약: 모든 필드 **snake_case**(P19), 시각은 **naive UTC**(`2026-09-08T03:32:54.932734`, `Z` 없음 — Dart에서 `Z`를 붙여 파싱).

---

## 1. GET /api/credits/me

- **요청**: 없음 (쿼리·바디 없음). 작성자는 `deps.get_current_user_id()` (P24).
- **응답**: `CreditSummaryResponse`

| 필드 | 타입 | nullable | 비고 |
|---|---|---|---|
| `user_id` | string | ✗ | |
| `nickname` | string | ✗ | `users.nickname` 조인. 사용자 행이 없으면 `"게스트"` |
| `balance` | int | ✗ | 현재 잔액 (원장 전체 합계) |
| `total_earned` | int | ✗ | 누적 획득 (원장 **양수만** 합계). 뱃지 판정 기준 |
| `badge` | object | ✗ | 항상 존재. 아래 `CreditBadge` |
| `badge.code` | string | ✗ | `SPROUT`/`VISITOR`/`EXPLORER`/`VETERAN`/`MASTER` |
| `badge.label` | string | ✗ | `새싹`/`Spot 탐방객`/`Spot 탐험가`/`베테랑`/`마스터` |
| `badge.emoji` | string | ✗ | `🌱`/`📍`/`🧭`/`🏆`/`👑` |
| `badge.min_credit` | int | ✗ | 현재 등급의 하한 (`0`/`50`/`100`/`200`/`500`). 진행바 시작점 |
| `badge.next_label` | string | **✓** | 최상위(MASTER)면 `null` |
| `badge.next_at` | int | **✓** | 다음 등급의 하한. 최상위면 `null` |
| `badge.remaining` | int | **✓** | 다음 등급까지 남은 크레딧. 최상위면 `null` |

- **실제 응답 (총 120크레딧 사용자)**:
```json
{
  "user_id": "00000000-0000-0000-0000-000000000001",
  "nickname": "테스트유저",
  "balance": 120,
  "total_earned": 120,
  "badge": {
    "code": "EXPLORER",
    "label": "Spot 탐험가",
    "emoji": "🧭",
    "min_credit": 100,
    "next_label": "베테랑",
    "next_at": 200,
    "remaining": 80
  }
}
```

- **실제 응답 (활동 이력 0인 사용자 — P23)**: HTTP **200**
```json
{"user_id":"seed_user_20","nickname":"테스트유저20","balance":0,"total_earned":0,"badge":{"code":"SPROUT","label":"새싹","emoji":"🌱","min_credit":0,"next_label":"Spot 탐방객","next_at":50,"remaining":50}}
```

- **에러**: 없다. 사용자가 없어도, 원장이 비어도 200 + 기본값이다(P23). 404/500을 내지 않는다 — 여기서 에러를 내면 마이 화면 전체가 못 그려진다.

### 뱃지 등급 컷 전수 (실측, `resolve_badge` 직접 호출)

| total_earned | code | label | min_credit | next_label | next_at | remaining |
|---|---|---|---|---|---|---|
| 0 | SPROUT | 새싹 | 0 | Spot 탐방객 | 50 | 50 |
| 49 | SPROUT | 새싹 | 0 | Spot 탐방객 | 50 | 1 |
| 50 | VISITOR | Spot 탐방객 | 50 | Spot 탐험가 | 100 | 50 |
| 99 | VISITOR | Spot 탐방객 | 50 | Spot 탐험가 | 100 | 1 |
| 100 | EXPLORER | Spot 탐험가 | 100 | 베테랑 | 200 | 100 |
| 199 | EXPLORER | Spot 탐험가 | 100 | 베테랑 | 200 | 1 |
| 200 | VETERAN | 베테랑 | 200 | 마스터 | 500 | 300 |
| 499 | VETERAN | 베테랑 | 200 | 마스터 | 500 | 1 |
| 500 | MASTER | 마스터 | 500 | **null** | **null** | **null** |
| 1000 | MASTER | 마스터 | 500 | **null** | **null** | **null** |

앱은 이 표를 복제하지 말 것(P22·P27). 서버가 컷을 바꿔도 앱이 옛 기준으로 그리게 되고, 그 어긋남은 아무 에러도 내지 않아 발견이 늦는다.

---

## 2. GET /api/credits/me/ledger

- **요청**: 쿼리 `limit` (int, 기본 **20**, 범위 1~100). 범위를 벗어나면 422.
- **응답**: **`CreditLedgerEntry`의 배열** (최상위가 배열). `created_at` 내림차순(최신순).

| 필드 | 타입 | nullable | 비고 |
|---|---|---|---|
| `id` | string | ✗ | 원장 행 id (UUID) |
| `amount` | int | ✗ | **음수 가능** (회수는 행 삭제가 아니라 음수 행). 현재는 `+10`/`+5`만 발생 |
| `reason` | string | ✗ | `REPORT` / `ANSWER` (대문자) |
| `source_type` | string | ✗ | `report` / `answer` (소문자) |
| `source_id` | string | ✗ | `report`면 report.id, **`answer`면 answer.id가 아니라 question.id** (질문당 1회, P14) |
| `created_at` | datetime | ✗ | naive UTC |

- **실제 응답 (`?limit=3`)**:
```json
[
  {
    "id": "1412312d-afb6-420a-9075-6e3bc5548f4a",
    "amount": 10,
    "reason": "REPORT",
    "source_type": "report",
    "source_id": "eb452231-1879-4e28-a23b-229c87542015",
    "created_at": "2026-09-08T03:32:54.932734"
  },
  {
    "id": "8b3ff24e-187c-45f6-9488-4ba626748d55",
    "amount": 10,
    "reason": "REPORT",
    "source_type": "report",
    "source_id": "29b2a303-a239-4e26-b68d-da176c26fc83",
    "created_at": "2026-09-08T03:32:54.907264"
  },
  {
    "id": "7759a420-957a-491c-9737-fe5058e9a99d",
    "amount": 10,
    "reason": "REPORT",
    "source_type": "report",
    "source_id": "f283bfab-2929-4da6-95fa-db886febfb71",
    "created_at": "2026-09-08T03:32:54.880781"
  }
]
```

- **실제 응답 (답변 적립 행 — `source_id`가 question_id임을 확인)**:
```json
[
  {
    "id": "22cdb340-55c2-487a-9cec-fd8e5302e721",
    "amount": 5,
    "reason": "ANSWER",
    "source_type": "answer",
    "source_id": "c97a9391-204b-4fff-bd65-ace4d30548be",
    "created_at": "2026-09-08T03:32:35.470109"
  }
]
```

- **실제 응답 (내역 없음)**: HTTP **200**, `[]` — 빈 배열이지 404가 아니다.
- **에러**: `limit`이 1~100 밖이면 422. 그 외 없음.

---

## 3. GET /api/credits/me/activity

- **요청**: 없음.
- **응답**: `ActivityCountResponse`

| 필드 | 타입 | nullable |
|---|---|---|
| `report_count` | int | ✗ |
| `answer_count` | int | ✗ |
| `question_count` | int | ✗ |

- **실제 응답**:
```json
{
  "report_count": 17,
  "answer_count": 0,
  "question_count": 4
}
```
- **실제 응답 (활동 0)**: HTTP 200, `{"report_count":0,"answer_count":0,"question_count":0}`
- **에러**: 없음.

### ⚠️ 앱 구현 주의 — 이 숫자로 크레딧을 역산하지 말 것

전체 기간 누적 **작성 건수**이고, 적립 여부와 무관하다. GPS 미인증·일일 상한 초과·시드 데이터로 크레딧을 받지 못한 글도 "내가 쓴 글"인 것은 사실이라 센다.

위 실측이 그 증거다: `report_count=17`인데 `total_earned=120`(= 제보 12건분)이다. 차이 5건은 시드 제보 + 상한에 걸린 4번째 제보다.
**`report_count * 10 + answer_count * 5 ≠ total_earned`가 정상이다.** 크레딧 숫자는 반드시 `/api/credits/me`의 `balance`·`total_earned`를 그대로 쓴다.

---

## 4. 기존 엔드포인트 — 응답 변화 없음 (P18)

`POST /api/reports`와 `POST /api/questions/{id}/answers`에 적립을 연결했지만 **응답 스키마는 키 하나도 건드리지 않았다.** 제보·답변 화면에 회귀가 없다.

적립 성공/실패는 응답에 전혀 드러나지 않는다. 상한 초과나 GPS 미인증으로 적립이 안 돼도 **HTTP 200 + 평소와 똑같은 응답**이다(P15) — 크레딧을 못 받았다고 정보 제공 자체를 막지 않기 위함. 앱이 "적립됐는지"를 알고 싶으면 제보/답변 성공 후 `/api/credits/me`를 다시 불러 비교해야 한다.

실측 (상한 초과된 4번째 제보, HTTP 200 · 저장됨 · 크레딧 변화 없음):
```json
{"id":"...","user_id":"00000000-0000-0000-0000-000000000001","user_nickname":"테스트유저","spot_content_id":"126508","crowdedness_level":"NORMAL","waiting_time":"UNDER_10","parking_status":"NORMAL","comment":"smoke 004","photo_url":null,"gps_verified":true,"created_at":"2026-09-08T03:31:57.276926"}
```

---

## 5. 적립 규칙 (구현 확정값)

| 항목 | 값 | 설정 키 |
|---|---|---|
| 제보 적립 | +10 | `CREDIT_AMOUNT_REPORT` |
| 답변 적립 | +5 | `CREDIT_AMOUNT_ANSWER` |
| 질문 적립 | 0 — **원장 행 자체를 만들지 않는다** | (상수 없음) |
| 같은 장소 하루 상한 | 3건 | `CREDIT_DAILY_LIMIT_PER_SPOT` |
| "하루"의 정의 | KST 자정 — `report_window.today_cutoff_utc()` **재사용**(복붙 아님) | |
| GPS 미인증 | `gps_verified=False`면 적립 없음 | |
| 제보 중복 방지 | `client_request_id` early-return (적립 경로를 아예 지나지 않음) | |
| 답변 중복 방지 | `source_id = question_id` + `UNIQUE(user_id, source_type, source_id)` | |

상한은 **장소별로 독립**이다. 실측: 4개 관광지에서 각 3건씩 적립되어 총 120크레딧(12건 × 10).

**⚠️ 상한은 행동 종류(제보/답변)를 구분하지 않고 장소 하나당 하루 3건을 공유한다.** `credit.py:137-147`이 `source_type`을 보지 않고 같은 `(user_id, spot_content_id, 날짜)`로만 판정한다. 예: 어떤 장소에 제보 3건으로 이미 상한을 채웠으면, 그 장소의 질문에 답을 달아도 적립되지 않는다(QA 04_qa_report.md O1 실측). **의도된 동작으로 확정한다** — 스펙 Q3-a("같은 장소 하루 3건까지만 적립")가 행동별 분리를 요구하지 않았고, "장소당 하루 N건"이라는 문구를 가장 단순하게 해석하면 행동과 무관한 공유 바구니가 맞다. 분리하려면 `services/credit.py`의 상한 판정 쿼리에 `source_type` 조건을 추가하는 별도 변경이 필요하다(이번 범위 아님).

---

## 6. 스모크 검증 결과 (전부 실서버 curl 실측)

| # | 시나리오 | 기대 | 실측 | 결과 |
|---|---|---|---|---|
| 1 | 활동 0인 사용자 `/credits/me` | 200 + 0 + SPROUT | 그대로 | ✅ |
| 2 | 제보 1건(GPS 인증) | balance/total_earned 0→10, remaining 50→40 | 그대로 | ✅ |
| 3 | **같은 `client_request_id`로 재제출** | 같은 제보 반환, 크레딧 **10 유지** | 10 유지 | ✅ |
| 4 | 같은 장소 2·3번째 제보 | 20 → 30 | 그대로 | ✅ |
| 5 | **같은 장소 4번째 제보** | HTTP 200 저장 + 크레딧 **30 유지** | 200, 30 유지 | ✅ |
| 6 | 답변 1건(타인 질문, GPS 인증) | 0 → 5 | 그대로 | ✅ |
| 7 | **같은 질문에 2번째 답변** | 답변 200 저장 + 크레딧 **5 유지** | 200, 5 유지 | ✅ |
| 8 | 다른 관광지 3곳 × 3건 | 30 → 60(VISITOR) → 90 → 120(EXPLORER) | 그대로 | ✅ |
| 9 | 뱃지 5단계 경계 10개 지점 | 1절 표대로, MASTER는 next_* 3개 null | 그대로 | ✅ |
| 10 | `/ledger` 최신순·`[]` 빈 배열 | 200 | 그대로 | ✅ |
| 11 | `/activity` | 200 | 그대로 | ✅ |

**스모크로 확인하지 못한 것 (정직하게 기록)**: `gps_verified=False` 건이 적립되지 않는 경로. 현재 `.env`가 `DEMO_BYPASS_GPS=false`라 반경 밖 제보는 403으로 거부되어 애초에 저장되지 않는다. `DEMO_BYPASS_GPS=true`로 켜야 재현되는데 그 설정 변경은 이번 범위 밖이라 코드 검사(`prepare_award`의 `if not gps_verified: return None`)로만 확인했다. **contract-qa가 이 경로를 확인하려면 `.env`에서 `DEMO_BYPASS_GPS=true`로 바꾸고 반경 밖 좌표로 제보한 뒤 크레딧이 안 오르는지 보면 된다** (확인 후 반드시 되돌릴 것).

---

## 7. 구현 노트 — 스펙 밖에서 내린 판단 3가지

계약(응답 shape)에는 영향이 없지만, 나중에 이 코드를 고칠 사람이 알아야 할 것들이다.

### (1) `balance`를 `users.credit_balance` 캐시가 아니라 원장 합계에서 읽는다

P3은 `credit_balance`를 캐시로 두라 했고 그대로 유지하며 적립 때마다 갱신한다. 다만 **읽기는 원장을 본다.**

이유: `balance`와 `total_earned`가 **한 응답에 같이 나간다.** 캐시가 어떤 이유로든 어긋나면 `balance > total_earned` 같은 눈에 보이는 모순이 화면에 뜬다. P1이 "진실은 원장 합계"라고 못박았으므로 화면에는 진실이 나가야 한다. 캐시는 계속 갱신하므로 향후 차감 로직은 그대로 쓸 수 있다.

### (2) 적립 판정을 `db.add()` **앞**으로 옮겼다 (`reports.py`)

적립 자격 판정이 SELECT를 돌리는데, `db.add(new_report)` 뒤에서 부르면 autoflush가 일어난다. 그러면 `client_request_id` 중복 시 발생할 `IntegrityError`가 기존 `try/except` **밖에서** 터져, "중복 제출이면 기존 제보를 그대로 돌려준다"는 관례(P12·P13①)가 깨진다.

그래서 `report_id = str(uuid.uuid4())`로 id를 미리 발급해 원장의 `source_id`로 쓰고, 판정 → `db.add(report)` → `db.add(ledger)` → 기존 `commit()` 순서로 배치했다. **커밋은 여전히 하나뿐이고 새 `commit()`을 추가하지 않았다**(P11).

`questions.py`도 같은 이유로 `db.add(answer)` 앞에서 판정한다. 여기는 `source_id`가 question_id라 답변 id에 의존하지 않아 더 단순하다.

### (3) 남아 있는 좁은 레이스 (미해결, 의도적)

같은 사용자가 **같은 질문에 두 답변을 동시에** 제출하면, 두 요청이 모두 "아직 지급 안 됨" SELECT를 통과한 뒤 `UNIQUE` 제약에서 한쪽이 `IntegrityError`로 실패할 수 있다. 이때 `create_answer`에는 `try/except`가 없어 그 요청 전체가 500이 되고 답변도 저장되지 않는다 (사용자가 재시도하면 정상 저장 + 적립 없음).

막지 않은 이유: SAVEPOINT로 감싸면 pending 상태인 답변까지 롤백 범위에 들어가 더 복잡한 실패 모드가 생기고, 순차 요청(현실의 거의 전부)은 SELECT 사전 검사로 이미 막힌다. 정상 경로에서는 재현되지 않으며, 실패해도 **크레딧이 두 번 나가는 일은 없다**(제약이 최종 방어선이므로). 문제가 실제로 관측되면 그때 닫는다.

---

## 8. 변경된 파일

| 파일 | 변경 |
|---|---|
| `livespot_backend/app/models/schemas.py` | 신규 4개 추가 (`CreditBadge`/`CreditSummaryResponse`/`CreditLedgerEntry`/`ActivityCountResponse`). **기존 스키마 무수정** |
| `livespot_backend/app/db/models/credit_ledger.py` | 신규 — `UNIQUE(user_id, source_type, source_id)` 포함 |
| `livespot_backend/app/db/models/__init__.py` | `CreditLedger` import 추가 |
| `livespot_backend/migrations/versions/12e638fbc565_add_credit_ledger_table.py` | 신규. `down_revision = '9285c2232240'`, **적용 완료**(`alembic upgrade head`) |
| `livespot_backend/app/services/credit.py` | 신규 — 적립 판정·상한·집계·뱃지 산출 (두 라우터 공유) |
| `livespot_backend/app/api/credits.py` | 신규 — 조회 전용 엔드포인트 3개 |
| `livespot_backend/app/api/router.py` | `credits` 라우터 등록 (`prefix="/credits"`) |
| `livespot_backend/app/api/reports.py` | `create_report`에 적립 연결. **early-return 2경로 무수정** |
| `livespot_backend/app/api/questions.py` | `create_answer`에 적립 연결 (기존 트랜잭션 안) |
| `livespot_backend/app/config.py` | `CREDIT_AMOUNT_REPORT`/`CREDIT_AMOUNT_ANSWER`/`CREDIT_DAILY_LIMIT_PER_SPOT` |
| `livespot_backend/.env.example` | 위 3개 상수 갱신 |

시드 데이터 백필(`scripts/seed_dev_data.py`)은 **하지 않았다** — 01_spec 6절이 "결정 필요"로 남긴 항목이고 확정 지시가 없었다. 기존 시드 제보에는 원장 행이 없어 크레딧 0으로 시작한다. 뱃지 상위 등급 시연이 필요하면 별도 지시를 받아 백필한다.
