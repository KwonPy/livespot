# QA 리포트 — AI 브리핑 (기능 10) (검증 1회차)

> 작성: 2026-09-07 / contract-qa
> 대조 기준: `_workspace/01_spec.md` 2.1·2.2절 · `02_backend_contract.md` · `03_flutter_wiring.md` + 양쪽 실제 소스
> 환경 제약: TourAPI(`apis.data.go.kr`) 아웃바운드 TCP 불가 (사전 확인된 환경 문제, 이번 작업의 결함 아님)

---

## 판정 요약

| 항목 | 통과 | 실패 | 미검증 |
|---|---|---|---|
| A. 필드명 교차 (중첩 포함) | 7/7 | 0 | 0 |
| B. Nullable 정합 | 5/5 | 0 | 0 |
| C. datetime 직렬화 (naive UTC) | 2/2 | 0 | 0 |
| D. 경로·라우터 등록·래핑 | 4/4 | 0 | 0 |
| E. 상수·상태 문자열 동기화 | 3/3 | 0 | 0 (관찰 1건) |
| F. 화면 견고성 (3분기) | 3/3 | 0 | 0 |
| G. 정책 준수 (P4·P6·P9·P11·P12) | 5/5 | 0 | 0 |
| 회귀 (`live.py` → `report_window.py`) | 1/1 | 0 | 0 |
| 실서버 200 경로 (TourAPI 경유) | — | — | **1** |

**실패 0건.** 미검증 1건(환경 제약)과 관찰 4건은 아래에 그대로 남긴다.

---

## 검증 방법에 대한 사전 고지 — "실측"의 범위

TourAPI 불가로 `/spots/{id}/briefing`이 실서버에서 404만 낸다. 계약서에 기록된 JSON 예시를
그대로 믿고 정적 대조로 끝내지 않기 위해, **프로덕션 소스를 수정하지 않는 out-of-tree 하네스**를
따로 만들어 `app.main:app`을 in-process ASGI로 태웠다
(`<scratchpad>/qa_briefing_probe.py`, 검증용 임시 파일).

- **고정값으로 대체한 것**: `tour_service.get_spot_detail`, `congestion_service.get_spot_congestion` (2개뿐)
- **실물 그대로 돌린 것**: 라우팅 · 의존성 주입 · 핸들러 로직 · **`response_model` 직렬화** ·
  DB 제보 조회 · Open-Meteo 날씨 · **실제 Gemini 호출** · 캐시 · 폴백 분기

즉 아래 "TOP-LEVEL KEYS"는 Pydantic 정의를 읽은 결과가 아니라 **직렬화된 JSON 바이트에서 뽑은
실제 키**다. 다만 TourAPI 응답 dict에서 값을 꺼내는 부분(`item.get("overview")`, `mapy`/`mapx`)만은
실물로 확인하지 못했다 — 이것이 유일한 미검증 항목이다.

Dart 쪽도 같은 원칙으로, 위 JSON 원문을 `Briefing.fromJson`에 그대로 넣어 `dart run`으로 **실행**했다.

---

## 통과 항목 (근거 포함)

### A. 필드명 교차 — 통과

`contract_diff.py` 자동 대조 (repo root 기준 실행):

```
=== Briefing  <->  BriefingResponse   [OK]
=== BriefingBasedOn  <->  BriefingBasedOn   [OK]
합계: 1 issue(s), 매칭 실패 0개
```
(유일한 1건은 `SpotDetail.homepage` UNREAD — 기능 10과 무관한 기존 항목)

실측 직렬화 JSON의 최상위 키 (4개 source 값 전부 동일):

```
TOP-LEVEL KEYS: ['based_on', 'content_id', 'full_briefing', 'generated_at', 'source']
based_on KEYS : ['has_congestion', 'has_report', 'has_weather']
```

Dart가 읽는 키 (`lib/models/briefing.dart:42-46`, `:72-74`):
`content_id` · `full_briefing` · `source` · `generated_at` · `based_on` /
`has_report` · `has_congestion` · `has_weather`

→ **7개 키 전부 문자 단위 일치. MISSING 0, UNREAD 0.** 중첩 객체 `based_on` 내부까지 대조 완료.

### B. Nullable 정합 — 통과

- 서버: `BriefingResponse`의 5필드 전부 `Optional` 없음 (`schemas.py:123-131`). `BriefingBasedOn` 3필드도 전부 `bool` 필수.
- Dart: 전부 non-null (`as String` / `as bool`), **`?? 기본값`이 한 곳도 없다.**
- 실패가 숨지 않는지 실행으로 확인 — `based_on`을 뺀 페이로드 투입 시:
  ```
  [missing based_on] 예외로 드러남: _TypeError
  ```
  (버그패턴 2-3 "필수 필드를 기본값으로 삼킴"의 반대 방향으로 올바르게 구현됨)

### C. datetime 직렬화 — 통과 (요청 확인사항 5)

서버 실측 원문: `"generated_at": "2026-09-06T15:51:39.115317"` — **`Z` 없는 naive UTC** 확인.

Dart `_parseUtc`(`briefing.dart:52-55`) 실행 결과:

```
[AI]        generatedAt.isUtc=true utc=2026-09-06T15:51:39.115317Z local=2026-09-07 00:51:39.115317
[Z-suffixed] utc=2026-09-06T15:51:39.000Z isUtc=true
```

→ UTC 15:51 → KST 00:51 (+9h). **9시간 오차 없음.** 서버가 나중에 `Z`를 붙여 보내도
이중 보정하지 않는다(tz 접미사 검사 존재).

### D. 경로 · 래핑 — 통과

| | 값 |
|---|---|
| 서버 | `main.py`의 `/api` + `router.py`의 `prefix="/spots"` + `@router.get("/{content_id}/briefing")` = `/api/spots/{content_id}/briefing` |
| 앱 | `constants.dart` `apiBaseUrl='http://127.0.0.1:8000/api'` + `api_service.dart:191` `_dio.get('/spots/$contentId/briefing')` |

→ 일치. 새 라우터가 아니라 기존 `spots.router` 재사용(Q5-A)이라 `include_router` 누락 위험 없음
(`router.py:6`에 이미 등록됨). 응답이 객체이고 Dart가 `Map<String, dynamic>`으로 받는다
(`api_service.dart:192`) — 래핑 일치.

### E. 상수 · 상태 문자열 — 통과

- 이번 기능이 추가한 백엔드 상수 4개(`GEMINI_MODEL`·`GEMINI_TIMEOUT_SECONDS`·`BRIEFING_CACHE_TTL_SECONDS`·`BRIEFING_COMMENT_LIMIT`)는 **전부 서버 전용**이고 `constants.dart`에 짝을 만들지 않았다. 판정을 서버가 하는 값을 앱에 복제하지 않는 원칙(버그패턴 5-2)을 지켰다. `.env.example`에도 4개 모두 반영됨.
- Dart가 비교하는 상태 문자열은 `'AI'`·`'CACHED_AI'` 둘뿐이고, 서버 `BriefingSource = Literal["AI","CACHED_AI","TEMPLATE","NONE"]`에 실재한다. **서버가 낼 수 없는 값으로 분기하는 죽은 코드 없음.**
- 관찰 O3(기존 죽은 상수)은 아래 관찰 절 참조.

### F. 화면 견고성 — 3분기 통과 (요청 확인사항 6)

`spot_detail_screen.dart:581-619`를 분기별로 추적한 결과, **세 상태가 서로 다른 위젯 트리**를 그린다:

| 상태 | 조건 | 코드 경로 | 결과 트리 |
|---|---|---|---|
| 로딩 | `_briefingLoading=true, _briefing=null` | `:586` 통과 → `:612` true | Container + "AI 브리핑" 배지 + `_buildBriefingSkeleton()` (회색 바 3줄) |
| 정상 | `_briefing != null` | `:586` 통과 → `:612` false | Container + 배지 (+ `:607`이 참이면 라벨) + `Text(_displayedBriefing)` 타이핑 |
| 실패 | `_briefingLoading=false, _briefing=null` | `:586`에서 조기 반환 | `SizedBox.shrink()` — 섹션 통째 소멸 |

- **겹침 없음**: 세 조건이 상호 배타적이고, 로딩 상태에서 본문 `Text`가 그려지는 경로가 없다.
- **깜빡임 없음**: 실패 경로의 `catch`(`:129`)와 `finally`(`:131`)가 같은 async 연속 실행 안에서
  연달아 `setState`를 호출하므로 프레임이 한 번만 빌드된다. 스켈레톤 → 소멸 사이에
  "빈 카드"나 에러 문구가 끼어드는 중간 프레임이 없다.
- **에러 상태와 빈 상태가 구분됨**: 이 기능에는 "빈 상태"가 존재하지 않는다 — 재료 부족은
  200 + `source="NONE"` + 안내문(정상 경로)이고, 섹션 소멸은 오직 네트워크 단절·404일 때뿐이다.
  버그패턴 1-1(에러를 빈 상태로 뭉갬)의 조건 자체가 성립하지 않는다.
- 타이핑 트리거가 응답 도착 후로 옮겨진 것 확인 (`:126` `_startBriefingTyping(briefing.fullBriefing)`).
  `initState`의 500ms `Future.delayed` 제거됨(`:56-71`에 없음).
- 이 섹션은 `FutureBuilder`가 아니라 `setState` 패턴이라 `snapshot.hasError` 항목은 해당 없음
  (상세페이지의 기존 `_fetchCongestion`·`_fetchLiveStatus`와 같은 패턴).

### G. 정책 준수 — 통과

**P4 — `source`별 라벨 (요청 확인사항 1). 이번 작업의 정직성 핵심.**

게터 정의는 정확히 요구된 형태다 (`briefing.dart:38`):
```dart
bool get isAiGenerated => source == 'AI' || source == 'CACHED_AI';
```
화면 분기는 이 게터 하나만 본다 (`spot_detail_screen.dart:607-608`):
```dart
if (briefing != null && briefing.isAiGenerated)
  Text('Gemini로 생성됨', ...)
```
**분기를 눈으로 추적한 것에 그치지 않고 5개 값을 실제로 실행했다**(`dart run`):

```
[AI]                   isAiGenerated=true  label=표시
[CACHED_AI]            isAiGenerated=true  label=표시
[TEMPLATE]             isAiGenerated=false label=미표시
[NONE]                 isAiGenerated=false label=미표시
[UNKNOWN(STALE_CACHE)] isAiGenerated=false label=미표시   ← 미지의 값도 안전 기본값
```
→ `TEMPLATE`·`NONE`·미지의 값에서 라벨이 붙는 경로가 **코드상 존재하지 않는다.**
로딩 중에는 `briefing == null`이라 `:607`의 첫 조건에서 걸러진다 — 문장 도착 전에 출처를
주장하는 상태가 없다.

**P12 — 하드코딩 잔재 제거 (요청 확인사항 2).** grep 재확인:
- `_demoBriefing` — **저장소 전체 0건**
- `'Gemini로 생성됨'` 문자열 리터럴 — **`spot_detail_screen.dart:608` 단 1곳**, 그것도 `:607` 조건 아래.
  (`briefing.dart:34`의 동일 문구는 문자열 리터럴이 아니라 `///` 문서 주석이다)
- `lib/providers/briefing_provider.dart` — **파일 삭제 확인** (`lib/providers/`에 `auth_`·`location_`·`spots_` 3개만 남음)

**폐기 필드 (요청 확인사항 3).** `summary_line`/`summaryLine`/폐기된 `weather`·`crowdedness` 필드가
브리핑 모델·화면에 남아 있지 않음:
- `lib/models/briefing.dart` — `summaryLine` 0건. `hasWeather`는 `based_on`의 정당한 필드이지 폐기된 `weather` 객체가 아니다. 중복 `CrowdednessInfo` 클래스 제거 확인(`congestion_info.dart`와 이름 충돌 해소).
- `spot_detail_screen.dart`의 브리핑 섹션이 그리는 문장은 `_displayedBriefing` 하나뿐(`:615`).
- `widgets/briefing_card.dart`의 `_buildSummaryLine`은 **지도 카드**로 C7에 의해 범위 밖이며, 서버 `summary_line`이 아니라 날씨·집중률을 앱이 이어 붙이는 별개 코드다. 변경 없음 확인.

**P6 — `CrowdednessService` 미사용.** `spots.py`에서 `crowdedness_service`가 호출되는 곳은
`:288` 레거시 `/crowdedness` 엔드포인트 하나뿐이다. 브리핑 핸들러(`:306-421`)에는 호출이 없고,
`:360`의 `report_crowdedness=latest.crowdedness_level`은 DB `Report` 컬럼이지 병합 서비스가 아니다.
예측(`congestion_service`)과 실측(`report_window`)을 각각 직접 호출한다.

**P9 — 앱이 Gemini를 직접 호출하지 않는다.** `livespot_app/lib`·`pubspec.yaml`에 `gemini`/`genai`/
`generativelanguage`/API 키 흔적 0건 (`weather.dart:17`의 주석 언급 1건 제외). SDK는 백엔드에만:
`requirements.txt:6 google-genai==1.46.0`, venv 설치 확인(1.46.0) — 01_spec (3)절의
`ModuleNotFoundError` 차단 항목이 해소됐다.

**P11 — 인증 불필요.** `spot_briefing(content_id, db=Depends(get_db))` — 인증·GPS 의존성 없음. 앱도 헤더 없이 호출.

### 회귀 — `live.py` → `report_window.py` 추출 (요청 확인사항 8) — 통과

DB 기반이라 TourAPI 없이 검증 가능했다. **실서버 curl 실측**:

```
GET /api/live/status/126508  →  HTTP 200
{"content_id":"126508","is_live":true,"recent_report_count":4,"current_crowdedness":"BUSY",
 "current_waiting_time":"OVER_30","current_parking_status":"FULL",
 "last_report_at":"2026-09-06T15:36:59.065091"}
```
`02_backend_contract.md:176-178`에 기록된 응답과 **키·값이 바이트 단위로 동일**하다.

코드로도 확인: `live.py:13-17`이 `report_window`에서 `latest_and_count`·`live_window_cutoff_utc`·
`today_cutoff_utc`를 **같은 이름으로 alias import**하고, `get_live_status`(`:44-55`)의 로직
(활동성=최근 2h / 현재상황=당일 KST)이 그대로다. `today_cutoff_utc()`의 KST 자정 → naive UTC
환산도 이전 구현과 동일(`report_window.py:31-33`). **동작 변경 없음.**

---

## 실패 (수정 필요)

**없음.**

---

## 미검증 항목과 이유

### U1. 실서버 `/briefing` 200 응답 (TourAPI 경유 경로) — 미검증

- **이유**: 이 개발 환경에서 `apis.data.go.kr`로의 TCP connect가 타임아웃된다(DNS는 해석됨).
  `tour_service.get_spot_detail()`이 빈 값을 돌려주므로 핸들러가 `:325`에서 즉시 404를 낸다.
  **사전에 확인된 환경 문제이며 이번 작업의 결함이 아니다.**
- **실측 근거**:
  ```
  GET /api/spots/126508/briefing  →  HTTP 404 {"detail":"관광지를 찾을 수 없습니다."}
  GET /api/spots/126508/weather   →  HTTP 404 (동일)   ← TourAPI 의존 엔드포인트 전부 동일 증상
  GET /api/live/status/126508     →  HTTP 200          ← DB 기반은 정상
  ```
- **대체 검증으로 덮은 범위**: 위 "사전 고지" 절 참조 — 라우팅·직렬화·DB·날씨·Gemini·캐시·
  폴백 4분기·404를 실물로 확인했으므로, 경계면 정합성 자체는 사실상 전부 검증됐다.
- **여전히 남는 공백 (TourAPI 복구 후 재검증 필요)**:
  1. TourAPI 응답 dict에서 재료를 꺼내는 부분 — `item.get("title")`·`item.get("overview")`·
     `mapy`(위도)/`mapx`(경도). 특히 `_collect_weather`(`spots.py:293-303`)의 위경도 뒤집힘은
     에러 없이 엉뚱한 지점 기온이 오는 종류라 실물 없이는 확인 불가.
  2. 실 TourAPI 지연을 포함한 **총 응답 시간** (관찰 O1과 직결).
  3. 계약서 7)의 "제보 직후 캐시 무효화" 실서버 재현.

### U2. 앱 실행 시 실제 렌더링 — 미검증

- **이유**: 지시대로 `flutter run`을 하지 않았다. 위젯 트리는 코드로 추적했고 모델·라벨 판정은
  `dart run`으로 실행 검증했으나, 스켈레톤·타이핑의 **시각적** 동작은 사용자 확인 몫이다.

---

## 관찰 (실패 아님 — 리더 판단용)

### O1. 앱 `receiveTimeout` 8초와 서버 최악 지연의 여유가 얇다 — **재측정 권고**

- `api_service.dart:29` `receiveTimeout: Duration(seconds: 8)`
- 서버 예산: `GEMINI_TIMEOUT_SECONDS=5.0` + TourAPI 상세조회 + 날씨 + 집중률 + DB 3쿼리
- `config.py`의 주석이 이 관계를 이미 인지하고 있다("앱의 receiveTimeout이 8초라 그보다 먼저 포기해야").
- **문제가 되는 시나리오**: Gemini가 5초를 다 쓰고 타임아웃된 뒤 TourAPI가 느리면 총합이 8초를
  넘길 수 있다. 그러면 서버는 정상적으로 200 + `TEMPLATE`을 만들어 보내는데 앱은 그 전에
  끊어져 catch로 떨어지고, **브리핑 섹션이 통째로 사라진다.** 폴백을 정성껏 만들어 놓고
  화면에는 아무것도 안 뜨는 형태가 된다.
- **현재 실측**: TourAPI 고정값 상태에서 템플릿 폴백 경로 2.3~2.5초, AI 경로 3.86초(계약서 기준).
  **이 환경에서는 재현되지 않았다.** TourAPI 복구 후 실지연을 포함해 재측정할 것.
- 조치가 필요하다고 판단되면 서버 `GEMINI_TIMEOUT_SECONDS`를 낮추거나 앱 `receiveTimeout`을
  올리는 쪽 중 하나를 선택하면 된다. **지금 고칠 근거는 없다 — 측정값이 없으므로 FAIL로 올리지 않는다.**

### O2. TourAPI 불가 상태에서 `/live/hotspots`가 빈 배열을 반환한다 — 기존 동작, 범위 밖

```
GET /api/live/hotspots  →  HTTP 200  []
```
제보는 실재한다(`/live/status/126508`이 `recent_report_count: 4`). 원인은 `live.py:96`
`if not detail: continue` — TourAPI로 관광지명을 붙이지 못한 후보가 전부 탈락한다.
결과적으로 앱 HOT SPOTS에는 "활동 중인 관광지가 없어요"라는 **빈 상태**가 뜬다(버그패턴 1-1의
서버 측 형태). **이번 작업이 손대지 않은 기존 코드이고 TourAPI 복구 시 자동 해소되므로 FAIL이
아니다.** 다만 이 상태로 시연하면 눈에 띄는 지점이라 기록해 둔다.

### O3. `constants.dart:3 gpsVerificationRadius = 500` — 미사용 죽은 상수, 삭제 권고

서버는 `GPS_VERIFICATION_RADIUS_M(100) + GPS_ERROR_MARGIN_M(50) = 150`으로 판정하고
GPS 판정은 전적으로 서버가 한다. 앱의 500은 어디에도 쓰이지 않는다.
**불일치가 아니라 미사용이다** — 기존 항목이며 이번 기능과 무관하다. 별건으로 삭제 권고.

### O4. `flutter-builder`가 남긴 미해결 이슈 2건 — 확인함, 의도된 보류

- 섹션 헤더 "AI 브리핑" 배지가 `source` 무관하게 항상 표시됨(`spot_detail_screen.dart:599`) — 확인함, 재검증 대상 아님.
- 제보 직후 인플레이스 갱신 없음(`:822-823`이 `_fetchReports()`·`_fetchLiveStatus()`만 호출) — 확인함, 재검증 대상 아님.

버그패턴 8-1(형제 위젯의 하드코딩 잔재) 관점에서 브리핑 섹션 안을 훑은 결과, 조건 없이
항상 렌더되는 문자열 리터럴은 위 "AI 브리핑" 배지 하나뿐이고 그것이 곧 보류 항목 2번이다.
그 외 새 실측값과 모순되는 인접 하드코딩 텍스트는 없다.

---

## 실행 검증 결과

### uvicorn 기동
**성공** (이미 기동 중인 인스턴스 재사용). `GET /health` → `200 {"status":"ok"}`

### curl 실측 (실서버, 포트 8000)

| 엔드포인트 | HTTP | 응답 최상위 키 |
|---|---|---|
| `/health` | 200 | `status` |
| `/api/spots/126508/briefing` | **404** | `detail` — TourAPI 불가 (U1) |
| `/api/spots/126508/weather` | **404** | `detail` — 동일 원인 |
| `/api/live/status/126508` | 200 | `content_id`, `is_live`, `recent_report_count`, `current_crowdedness`, `current_waiting_time`, `current_parking_status`, `last_report_at` |
| `/api/live/hotspots` | 200 | `[]` (관찰 O2) |

### in-process ASGI 실측 (TourAPI·집중률만 고정값, 나머지 실물)

| 케이스 | HTTP | `source` | 최상위 키 | `based_on` 키 |
|---|---|---|---|---|
| 최초 호출 | 200 | `AI` | `based_on, content_id, full_briefing, generated_at, source` | `has_congestion, has_report, has_weather` |
| 재호출 | 200 | `CACHED_AI` | 동일 | 동일 |
| Gemini 실패 강제 | 200 | `TEMPLATE` | 동일 | 동일 |
| 재료 부족 | 200 | `NONE` | 동일 | 동일 |
| 없는 관광지 | 404 | — | `detail` | — |

부수 확인: `CACHED_AI`의 `generated_at`이 최초 `AI` 응답과 동일(`15:51:39.115317`) — 캐시가
원래 생성 시각을 보존한다. `TEMPLATE`·`NONE` 본문에 예외 메시지·스택 흔적 없음(P2).
실제 Gemini 호출이 성공했다 — 즉 현재 `.env`의 키와 `GEMINI_MODEL`이 유효하다
(01_spec Q7의 "키 무효" 차단 항목이 해소된 상태).

### Dart 실행 검증 (`dart run`, 위 실측 JSON 원문 투입)

5개 `source` 값 + `Z` 접미사 변형 + 키 누락 케이스 전부 통과 (본문 C·G절에 결과 인용).
검증용 임시 파일은 실행 후 삭제했다 — 저장소에 남긴 파일 없음.

### dart analyze

```
73 issues found.   (info 69 · error 2 · warning 2)
```
- **이번 작업이 손댄 파일의 신규 지적 0건** — `flutter-builder`의 주장을 직접 재현했다:
  - `lib/models/briefing.dart` — **지적 0건**
  - `lib/services/api_service.dart` — `avoid_print` 2건(`:70`, `:84`)뿐. 둘 다 `fetchSpots` 영역의 기존 코드이며 신규 `fetchBriefing`(`:190-193`)에는 지적 없음
  - `lib/screens/detail/spot_detail_screen.dart` — `withOpacity` deprecation 4건(`:426`, `:564`, `:770`, `:803`)뿐. **브리핑 섹션 라인 범위(`:581-637`)에 지적 0건**
- error 2건은 범위 밖 기존 부채: `auth_service.dart:1` `firebase_auth` 미설치,
  `test/widget_test.dart:16` `MyApp` 미정의.
- `flutter analyze`가 아니라 `dart analyze`를 쓴 이유는 008 일지와 동일 — 프로젝트 경로에
  한글이 섞여 analysis server가 죽는다.
- **한계 명시**: 이 저장소는 git 저장소가 아니라 착수 전 트리와 기계적으로 diff할 수 없다.
  "신규 0건"은 손댄 3개 파일의 지적이 전부 기존 코드 라인이고 기존 카테고리
  (`withOpacity` deprecation / `avoid_print`)에 속함을 라인 단위로 확인한 결과다.

### `flutter run`
지시대로 **실행하지 않았다.**

---

## 다음 검증(2회차)에서 반드시 다시 볼 것

TourAPI 복구 후:
1. `/api/spots/126508/briefing` 200 실응답의 실제 키 목록 (U1-1)
2. 실 TourAPI 지연을 포함한 총 응답 시간 vs 앱 `receiveTimeout` 8초 (O1)
3. 날씨 좌표 `mapy`=위도 / `mapx`=경도가 뒤집히지 않았는지 (기온이 엉뚱한 지역 값이 아닌지)
4. 제보 1건 등록 → 상세페이지 재진입 시 `source`가 `CACHED_AI` → `AI`로 바뀌는지 (계약서 7)
5. `/api/live/hotspots`가 다시 채워지는지 (O2 자동 해소 확인)
