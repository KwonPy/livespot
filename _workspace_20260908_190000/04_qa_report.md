# QA 리포트 — Credit + 뱃지 (기능 4 · 11) (검증 1회차)

> 작성: 2026-09-08 / contract-qa
> 근거: `01_spec.md` 2절·2.1.1절, `02_backend_contract.md`, `03_flutter_wiring.md` + 양쪽 실제 소스 + **실서버 curl 실측**
> 서버: uvicorn 127.0.0.1:8000, `.env` = `TEST_MODE=true` / `SERVICE_AREA_FILTER=none` / `DEMO_BYPASS_GPS` 미설정(=False), alembic head `12e638fbc565`

---

## 판정 요약

| 항목 | 통과 | 실패 | 관찰(수정 불요) | 미검증 |
|---|---|---|---|---|
| A. 필드명 교차 (3 엔드포인트 + 중첩 badge) | 3/3 | 0 | 1 | 0 |
| B. Nullable 정합 (next_label/next_at/remaining, nickname, source_id) | 6/6 | 0 | 0 | 0 |
| C. datetime 직렬화 (`created_at`) | 1/1 | 0 | 0 | 0 |
| D. 경로 · 라우터 등록 · 래핑(배열/객체) | 3/3 | 0 | 0 | 0 |
| E. 상수 · 상태 문자열 동기화 | 3/3 | 0 | 0 | 0 |
| F. 화면 견고성 (FutureBuilder 3개) | 3/3 | 0 | 1 | 0 |
| G. 정책 준수 (P1~P27) | 25/27 | 0 | 2 | 0 |
| 실행 검증 (적립·상한·중복·GPS) | 8/8 | 0 | 0 | 1 (동시성 재현) |

**실패(수정 필요) 0건.** 관찰 4건은 아래 "관찰" 절에 분리했고, 전부 리더 판단 사항이지 재작업 지시 대상이 아니다.

---

## 1. 리더가 확인을 지시한 3가지 (backend → flutter 전달 사항) — 전부 반영됨

### (1) `badge.next_label`/`next_at`/`remaining` nullable — **반영 확인 (실측)**

Pydantic (`schemas.py:314-316`)이 `Optional[...] = None`, Dart(`credit_summary.dart:87-89`)가 `as String?` / `as int?`. 문자 단위 일치.

MASTER 등급 응답을 **실제 HTTP로 재현**했다(원장에 임시 600점 행을 넣고 조회 후 즉시 삭제, 잔여 0건 확인):

```json
{"user_id":"seed_user_29","nickname":"테스트유저29","balance":600,"total_earned":600,
 "badge":{"code":"MASTER","label":"마스터","emoji":"👑","min_credit":500,
          "next_label":null,"next_at":null,"remaining":null}}
badge keys: ['code','emoji','label','min_credit','next_at','next_label','remaining']
```

키가 **누락되지 않고 명시적 `null`로** 내려온다(`response_model_exclude_none` 미적용 확인). Dart는 키 누락/`null` 양쪽 모두 안전.
화면 분기도 안전하다 — `CreditBadge.isMax`(`credit_summary.dart:79`)가 `nextLabel == null`로만 판정하고, `credit_ledger_screen.dart:117-119`가 `isMax`일 때 `remaining!`을 절대 읽지 않는다. 진행바를 안 그렸으므로 `nextAt` 산술도 없다.

### (2) `/me/ledger` 최상위 배열 — **반영 확인 (실측)**

```
curl "…/api/credits/me/ledger?limit=3" → toplevel type: list
item keys: ['amount','created_at','id','reason','source_id','source_type']
```
Dart `api_service.dart:341` — `final List<dynamic> data = response.data;` 로 바로 받는다. `Map` 언랩 시도 없음. `limit` 경계 실측: `0→422`, `100→200`, `101→422`. 앱은 `limit: 100` 고정이라 항상 유효 구간.

### (3) `/activity`가 총 작성 건수 — **역산 없음 확인**

`profile_screen.dart`는 `activity.reportCount`·`activity.answerCount`를 제보/답변 칸에만 쓰고, Credit 칸은 `stats.credit.balance`를 그대로 쓴다(`profile_screen.dart:282, 291, 300`). 곱셈·합산 코드가 어디에도 없다.

**실측으로 두 값이 실제로 갈리는 것까지 확인**했다 — 상한에 걸린 4번째 제보 후:
```
/activity  → {"report_count":4,"answer_count":3,"question_count":0}
/credits/me → balance 35, total_earned 35     (4×10+3×5=55 ≠ 35)
```
앱이 역산했다면 여기서 어긋났을 것이다. 안 한다.

---

## 2. flutter-builder가 스스로 보고한 판단 2건 — 둘 다 타당

### (1) `nickname`·`source_id`를 non-null로 좁힘 — **타당 (백엔드 대조 완료)**

| 값 | 서버 근거 | 판정 |
|---|---|---|
| `nickname` | `schemas.py:323` `nickname: str` (Optional 아님) + `db/models/user.py:18` `nullable=False` + `services/credit.py:225` 사용자 행이 없을 때도 `"게스트"` 채움 | non-null 맞다 |
| `source_id` | `schemas.py:339` `source_id: str` + `db/models/credit_ledger.py:39` `nullable=False` | non-null 맞다 |

`?? 기본값`으로 삼키지 않고 `as String`으로 받은 것도 규약대로다(필수 필드는 없으면 예외가 나야 드러난다).

### (2) `reason` → 한글 라벨 매핑을 Dart에서 — **P22/P27 위반 아님. 유지 권장**

- **서버가 안 주는 게 맞다**: `CreditLedgerEntry`(`schemas.py:329-340`)에 `reason_label` 필드 없음. curl 실측 키 목록에도 없다.
- **P22/P27의 대상이 아니다**: 두 조항은 *뱃지 등급 판정*(어떤 숫자가 어느 등급인가)을 앱이 하지 말라는 것이다. `reasonLabel`은 판정이 아니라 enum 코드의 표기이고, 이 프로젝트에 이미 같은 관례가 있다 — `crowdedness_badge.dart:14` `CrowdednessBadge.labelFor`.
- **폴백이 안전하다**: `credit_ledger_entry.dart:46-55`가 모르는 코드는 지어내지 않고 원문을 그대로 표시한다. 서버에 새 사유가 추가돼도 화면이 조용히 틀린 말을 하지 않는다.
- 실제로 앱에 등급 컷·라벨·이모지가 복제되지 않았음을 전수 grep으로 확인: `lib/**/*.dart`에서 `새싹|탐방객|탐험가|베테랑|마스터|SPROUT|VISITOR|EXPLORER|VETERAN|MASTER` 히트 **3건, 전부 주석**(`credit_summary.dart:47,50`, `profile_screen.dart:257`). 코드 0건. `constants.dart` 무수정.

---

## 3. 자동 대조 (`contract_diff.py`)

```
=== CreditBadge        <-> CreditBadge             [OK]  credit_summary.dart
=== CreditSummary      <-> CreditSummaryResponse   [OK]  credit_summary.dart
=== CreditLedgerEntry  <-> CreditLedgerEntry       [OK]  credit_ledger_entry.dart
=== ActivityCounts     <-> ActivityCountResponse   [OK]  activity_counts.dart
=== Report             <-> ReportResponse          [OK]  report.dart        (P18 회귀 없음)
=== Answer             <-> AnswerResponse          [OK]  question.dart      (P18 회귀 없음)
합계: 1 issue — Spot/SpotDetail의 `homepage` UNREAD (이번 기능과 무관, 선재 항목)
```
매칭 실패 0개. 신규 4개 모델 전부 MISSING/UNREAD/NULLABLE/UTC 0건.

### curl 실측 키 ↔ Dart `fromJson` 대조 (실행 검증)

| 엔드포인트 | 실제 응답 최상위 키 (curl) | Dart가 읽는 키 | 판정 |
|---|---|---|---|
| `GET /api/credits/me` | `['badge','balance','nickname','total_earned','user_id']` | 동일 5개 | ✅ |
| ↳ `badge` | `['code','emoji','label','min_credit','next_at','next_label','remaining']` | 동일 7개 | ✅ |
| `GET /api/credits/me/ledger` | (list) `['amount','created_at','id','reason','source_id','source_type']` | 동일 6개 | ✅ |
| `GET /api/credits/me/activity` | `['answer_count','question_count','report_count']` | 동일 3개 | ✅ |

서버 `credit_ledger` 테이블에는 `spot_content_id` 컬럼이 있으나 `CreditLedgerEntry` 스키마에 없어 **응답에 나가지 않는다**(실측 키 목록으로 확인). Dart도 안 읽는다 — 일치.

---

## 4. C~F 항목 상세

**C. datetime** — 서버 `created_at`은 naive UTC(`2026-09-08T03:32:54.932734`, `Z` 없음). Dart `credit_ledger_entry.dart:3-6` `_parseUtc`가 tz 없으면 `Z`를 붙여 파싱. 소비처인 `Formatters.reportRecency`(`formatters.dart:30-40`)도 `_toKst = date.toUtc().add(9h)`, `timeAgo`도 `DateTime.now().toUtc().difference(date.toUtc())` — **양쪽 다 UTC로 정규화 후 비교**한다. 9시간 어긋남 경로 없음.

**D. 경로·등록·래핑** — `router.py:13` `include_router(credits.router, prefix="/credits")` 등록 확인(404 원인 배제). 전체 경로 `/api` + `/credits` + `/me…`. Dart `apiBaseUrl='http://127.0.0.1:8000/api'` + `_dio.get('/credits/me')` = 일치. 실제 200 응답으로 확인. 객체 응답 2개는 `Map`, 배열 응답 1개는 `List<dynamic>`로 정확히 받는다.

**E. 상수·상태 문자열** — `config.py:62-68` `CREDIT_AMOUNT_REPORT=10`/`CREDIT_AMOUNT_ANSWER=5`/`CREDIT_DAILY_LIMIT_PER_SPOT=3`, 2.1.1절 확정값과 일치. `.env`에 오버라이드 없음(실측). **`constants.dart`에 대응 상수가 하나도 추가되지 않았다** — 판정을 전부 서버가 하므로 이게 정답이다(불일치 아님). Dart의 상태 문자열 비교 대상은 `reason == 'ANSWER'` 하나뿐이고 서버가 실제로 내는 값(`REPORT`/`ANSWER`)에 실재한다. 서버가 낼 수 없는 값으로 분기하는 죽은 코드 없음.

**F. 화면 견고성** — 신규·수정된 `FutureBuilder` 3개 전부 `hasError` 별도 분기:

| 위치 | waiting | hasError | isEmpty | data |
|---|---|---|---|---|
| `profile_screen.dart:240` `_buildStatsSection` | 회색 스켈레톤 박스 | 스탯 `'-'` + **빨간 배너 + 다시 시도** | (해당 없음) | 숫자 |
| `credit_ledger_screen.dart:80` `_buildSummaryCard` | 스피너 | **빨간 배너**(원문 메시지) | (해당 없음) | 파란 카드 |
| `credit_ledger_screen.dart:149` `_buildLedgerList` | 스피너 | **빨간 배너** | 회색 '아직 적립 내역이 없어요' | 목록 |

에러 화면과 빈 화면이 색·아이콘·문구까지 완전히 다르다. `snapshot.data ?? []`로 에러를 뭉개는 패턴(과거 HOT SPOTS 버그) 없음. 실패 시 `0`을 그리지 않는 것도 확인(`profile_screen.dart:245` — `failed`면 `stats`를 강제로 `null`로 만들어 `'-'` 경로로 보낸다).

---

## 5. 실행 검증 — 실제 POST로 재현한 8개 시나리오

backend-builder의 스모크를 신뢰하지 않고 **전부 독립 재현**했다. 사용자는 `seed_user_25/27/29`, 장소는 경복궁(`126508`, 37.576031/126.976722)과 `126507`.

| # | 시나리오 | 기대 | 실측 | 판정 |
|---|---|---|---|---|
| 1 | 활동 0 사용자 `/credits/me` | 200 + 0 + SPROUT | `{"balance":0,"total_earned":0,"badge":{"code":"SPROUT",…,"remaining":50}}` | ✅ P23 |
| 2 | GPS 인증 제보 1건 | 0 → 10 | balance 0 → **10** | ✅ |
| 3 | **같은 `client_request_id` 재제출** | 같은 report id 반환, 크레딧 10 유지 | 두 응답 모두 `id=8ad22c76-…`, balance **10 유지** | ✅ **P12 독립 재현 완료** |
| 4 | 같은 장소 2·3번째 제보 | 20 → 30 | 20 → **30** | ✅ |
| 5 | **같은 장소 4번째 제보** | HTTP 200 저장 + 크레딧 30 유지 | `http=200`, balance **30 유지** | ✅ P15 |
| 6 | 다른 장소 답변 1건 | +5 | 30 → **35**, 원장 `5 ANSWER answer 16cce2d0…` | ✅ |
| 7 | **같은 질문 2번째 답변** | 답변 200 저장 + 크레딧 5 유지 | `http=200`, balance **35 유지**, `source_id`가 question_id임을 원장에서 확인 | ✅ P14 |
| 8 | **`gps_verified=False` 제보** (아래 참조) | 200 저장 + 적립 0 | `gps_verified=False`, ledger `[]`, balance **0**, `/activity report_count=1` | ✅ Q3-b |

### 시나리오 8 — backend-builder가 "실측 못 했다"고 남긴 GPS 미인증 경로를 **실측으로 닫았다**

`.env`를 **수정하지 않고**, uvicorn 프로세스에만 `DEMO_BYPASS_GPS=true` 환경변수를 주입해 재기동한 뒤 서울 관광지(`126508`)에 부산 좌표(35.1796/129.0756, 거리 326,036m)로 제보:

```
POST /api/reports → http 200, gps_verified=False
GET  /api/credits/me        → balance 0, total_earned 0
GET  /api/credits/me/ledger → []
GET  /api/credits/me/activity → {"report_count":1,…}   ← 제보는 세지만 크레딧은 0
```

`services/credit.py:120-121`의 `if not gps_verified: return None`이 실제로 동작한다. 검증 후 서버를 기본 설정으로 재기동해 **환경은 원상 복구**했다(`.env` 무변경).

### 부수 확인 (DB 직접 조회)

- `credit_ledger` 테이블에 `CONSTRAINT uq_credit_ledger_user_source UNIQUE (user_id, source_type, source_id)` 실재 — P13② 최종 방어선 확인.
- 마이그레이션 `12e638fbc565` `down_revision='9285c2232240'`, `alembic current` = `12e638fbc565 (head)` — P7 확인.
- **캐시 드리프트 0건**: 원장이 있는 3명 전원 `users.credit_balance == SUM(ledger.amount)` (120/120, 5/5, 35/35).
- **P9 확인**: 질문 2건을 작성한 `seed_user_28`의 원장 행 수 = **0**. 질문은 원장 행조차 만들지 않는다.
- **P18 확인**: 제보·답변 응답 키가 기존과 동일(`id, user_id, user_nickname, spot_content_id, crowdedness_level, waiting_time, parking_status, comment, photo_url, gps_verified, created_at` / `id, question_id, user_id, user_nickname, content, created_at`). `contract_diff.py`도 `Report↔ReportResponse`, `Answer↔AnswerResponse` OK.

### `flutter analyze` (환경 제약으로 `dart analyze` 사용 — 동일 분석기)

```
73 issues found.
```
- **신규 5개 파일(`credit_summary.dart`, `credit_ledger_entry.dart`, `activity_counts.dart`, `credit_badge.dart`, `credit_ledger_screen.dart`) 지적 0건** — 파일별 집계에 아예 등장하지 않는다.
- `api_service.dart` 2건은 `:73`·`:87`의 선재 `avoid_print`(로그 인터셉터). 신규 메서드(`:325-354`) 지적 0건.
- `profile_screen.dart` 5건은 전부 `withOpacity` deprecation(`:188 :196 :255 :401 :412`). 관찰 4 참조.
- error 2건은 선재(`auth_service.dart` firebase_auth 미설치, `test/widget_test.dart` MyApp 부재). 이번 범위 밖.

---

## 6. 실패 (수정 필요)

**없다.** 이번 회차에서 재작업을 지시할 항목은 발견되지 않았다.

---

## 7. 관찰 (FAIL 아님 — 리더 판단 사항)

### O1. 답변 적립이 제보와 **같은 장소 일일 상한 3건 바구니를 공유**한다 — 문서 미기재 [심각도: 낮음, 문서 갱신 권고]

- 경계면: `livespot_backend/app/services/credit.py:137-147` ↔ `_workspace/02_backend_contract.md` 5절 "같은 장소 하루 상한 | 3건"
- 증거 (실측): `seed_user_29`가 `126508`에서 제보 3건으로 상한을 채운 뒤, **같은 장소의 질문에 답변**했더니
  ```
  POST /questions/{id}/answers → http=200 (답변은 정상 저장)
  balance 30 → 30 (적립 0)
  ```
  대조군으로 다른 장소(`126507`)에서 답변하니 30 → **35**로 정상 적립됐다.
- 원인: 상한 카운트가 `CreditLedger.spot_content_id == …` + `amount > 0`만 보고 `source_type`을 구분하지 않는다. 답변 적립도 `spot_content_id=question.spot_content_id`로 같은 버킷에 들어간다.
- 결과: "한 관광지에서 열심히 제보한 사람은 그날 그 관광지의 Q&A에 답해도 크레딧이 0"이 된다. 화면에는 아무 안내가 없다(P15상 응답은 200 그대로).
- 판정: `01_spec.md` Q3-a 확정문("같은 장소 하루 3건만")이 *행동별로 나눈다*고 명시하지 않았으므로 **스펙 위반은 아니다.** 다만 `02_backend_contract.md` 5절에 이 교차 효과가 적혀 있지 않아, 다음 사람이 "답변이 왜 적립 안 되지"를 다시 추적하게 된다.
- 권고: 리더 판단으로 둘 중 하나. ① 현행 유지 + `02_backend_contract.md` 5절과 작업일지에 "제보·답변이 장소별 3건을 공유한다" 한 줄 추가(비용 0), ② `source_type`별로 상한을 분리(백엔드 쿼리 1줄, 정책 재확정 필요).

### O2. `credit_summary.dart:47` 주석의 뱃지 코드 예시가 틀렸다 [심각도: 낮음]

```dart
/// 서버 내부 코드(SEEDLING/EXPLORER/…). 화면에는 쓰지 않고 로그·QA 대조용.
```
서버 실제 값은 `SPROUT`이다(`services/credit.py:41`, curl 실측 `"code":"SPROUT"`). **주석만 틀렸고 코드는 `code`로 분기하지 않으므로 동작에는 영향이 없다.** 다만 "QA 대조용"이라고 적힌 주석이 대조 기준을 틀리게 알려주는 상태라 다음 검증자를 오도한다. → flutter-builder, 주석 한 줄 정정 권고.

### O3. `credit_ledger_screen.dart:200` — 모르는 `reason`이 제보 아이콘으로 표시된다 [심각도: 낮음]

```dart
entry.reason == 'ANSWER' ? Icons.question_answer_outlined : Icons.edit_note,
```
`reasonLabel`(`credit_ledger_entry.dart:46-55`)은 모르는 코드를 원문 그대로 보여주는 안전한 폴백을 갖췄는데, 바로 옆 아이콘은 else 하나라 **미래의 회수/이벤트 사유가 "제보" 아이콘을 달게 된다.** 지금은 서버가 `REPORT`/`ANSWER`만 내므로 재현되지 않는다. 사유가 늘어날 때 같이 손보면 된다. (과거 패턴 8-1 "하나만 진짜가 되면 옆의 가짜가 눈에 띄게 틀려짐"의 예비 지점으로 기록.)

### O4. `profile_screen.dart:255`의 `withOpacity`가 새로 쓴 블록 안에 있다 [심각도: 낮음]

`_buildStatsSection`은 이번에 새로 작성됐는데, 그 안의 컨테이너 스타일 줄이 기존 원문을 그대로 옮겨와 `withOpacity`(deprecated)를 쓴다. 반면 같은 작업의 신규 파일 `credit_ledger_screen.dart`·`credit_badge.dart`는 `withValues`를 쓴다.
**총 이슈 수는 늘지 않았고**(기존 스타일 줄 이동), 나머지 4건(`:188 :196 :401 :412`)은 손대지 않은 코드다. 이 파일 전체가 `withOpacity` 60여 건짜리 선재 부채의 일부이므로 이번 범위에서 고칠 필요는 없다. 별건으로 남긴다.

---

## 8. 미검증 항목과 이유

| 항목 | 이유 |
|---|---|
| **동시 요청 레이스 (`02_backend_contract.md` 7-(3))** | 재현 **시도했으나 실패**. 같은 사용자가 같은 질문에 답변 2건을 동시 POST → 두 요청 모두 `http=200`, 답변 2건 저장, **원장 1행·크레딧 5점(이중 지급 없음)**. SQLite가 쓰기를 직렬화해 500이 나지 않았다. 즉 "이중 지급 위험"은 실측상 없음이 확인됐고, backend-builder가 경고한 500 경로만 재현하지 못했다. PostgreSQL 등 동시 쓰기가 실제로 겹치는 환경에서는 여전히 열려 있는 위험이므로 **미해결(수용된 리스크)로 유지**한다 |
| **`flutter run` 실제 화면 렌더** | 하네스 규약상 앱 구동 확인은 사용자 몫. 스켈레톤/에러 배너/빈 상태의 시각적 구분은 코드로만 확인했다 |
| **`dart analyze` 착수 전 baseline 73건 동일 여부** | 이 저장소는 git 저장소가 아니라 변경 전 상태를 되돌려 세어볼 수단이 없다. **검증한 것은 "현재 73건이며 신규 5개 파일 지적 0건, api_service 신규 메서드 지적 0건"**이고, "73 = 정확히 baseline"이라는 등식 자체는 독립 확인 불가 |
| **로그인 붙은 뒤의 `me` 동작** | 범위 밖(Q5-A로 이번 제외). 현재는 `X-Test-User-Id` 헤더 전환으로 사용자별 분리가 실동작함을 curl로 확인했다 |

---

## 9. 실행 검증 결과 (요약)

- **uvicorn 기동**: 성공 (`/health` → `{"status":"ok"}`). 검증 중 `DEMO_BYPASS_GPS=true`로 1회 재기동 후 **기본 설정으로 복구 완료**, `.env` 무변경.
- **alembic**: `current = 12e638fbc565 (head)`.
- **curl 실측 (응답 최상위 키)**:
  - `GET /api/credits/me` → `['badge','balance','nickname','total_earned','user_id']`, `badge` → `['code','emoji','label','min_credit','next_at','next_label','remaining']`
  - `GET /api/credits/me/ledger?limit=3` → **list**, item → `['amount','created_at','id','reason','source_id','source_type']`
  - `GET /api/credits/me/activity` → `['answer_count','question_count','report_count']`
- **쓰기 경로 실측**: `POST /api/reports` 6건, `POST /api/questions` 3건, `POST /api/questions/{id}/answers` 5건.
- **dart analyze**: 73 issues (신규 파일 0건, error 2건은 선재).

### 검증이 남긴 데이터 (개발 DB `livespot_backend/livespot.db`)

QA 재현 과정에서 `seed_user_25/26/27/28/29`에 제보·질문·답변·원장 행이 생겼다(예: `seed_user_29` balance 35). 임시로 넣었던 MASTER 등급 원장 행(`QA_TMP_MASTER`)은 **삭제 후 잔여 0건을 확인**했다. 나머지는 개발 시드 성격이라 남겨뒀다 — 뱃지 상위 등급 시연이 필요하면 이 사용자들을 쓰면 되고, 깨끗한 상태가 필요하면 `scripts/seed_dev_data.py`를 다시 돌리면 된다.

---

## 10. 리더 보고 요약

- **재작업 지시 대상: 없음.** 3개 엔드포인트의 경로·필드명·중첩·nullable·배열 래핑·UTC 처리가 계약과 문자 단위로 일치하고, 실제 서버 응답으로 확인했다.
- backend → flutter 전달 3건, flutter 자체 보고 2건 **전부 정확히 반영·타당**.
- backend-builder가 정직하게 남긴 미검증 항목(**GPS 미인증 시 미적립**)을 QA가 실측으로 닫았다. 통과.
- 남은 판단 사항은 **O1(답변이 제보와 장소 상한을 공유하는 것을 문서화할지)** 하나. 나머지 3건(O2 주석 오기, O3 아이콘 폴백, O4 lint)은 다음 작업 때 묶어 처리하면 되는 수준이다.
- 작업일지에 반드시 남길 것: O1의 교차 효과, 시나리오 8의 GPS 실측 방법(`.env` 수정 없이 환경변수 주입), 동시성 레이스가 SQLite에서는 재현되지 않으며 이중 지급은 발생하지 않는다는 사실.
