# 프론트 연결표: AI 브리핑 (기능 10)

> 작성: 2026-09-07 / flutter-builder
> 근거: `_workspace/02_backend_contract.md`(응답 스키마·실측 JSON) · `_workspace/01_spec.md` 2.1절 Q2·Q6·Q8, 6절 "영향 범위 > 프론트"
> 이 표가 `contract-qa`의 대조 기준이다.

---

## 화면-엔드포인트 연결표

| 화면/위젯 | 호출 메서드 | 엔드포인트 | 읽는 JSON 키 | 에러 분기 |
|---|---|---|---|---|
| `spot_detail_screen._buildAiBriefingSection` (`:581`) | `fetchBriefing` | `GET /api/spots/{content_id}/briefing` | `content_id`, `full_briefing`, `source`, `generated_at`, `based_on.has_report`, `based_on.has_congestion`, `based_on.has_weather` | ✅ 섹션 숨김 (Q6 확정 — 배너 아님) |

**에러 분기가 "배너"가 아닌 이유**: 백엔드 계약상 관광지 자체가 없을 때(404)를 빼면 **항상 200**이다.
AI 키 오류·타임아웃·쿼터 소진·재료 부족이 전부 200 + `source`(TEMPLATE/NONE)로 표현되므로
앱에 "AI 실패" 상태가 존재하지 않는다. catch에 걸리는 건 네트워크 단절과 404뿐이고, 그때는
Q6 확정대로 **섹션 자체를 숨긴다**(에러 문구를 띄우지 않는다 — 날씨 배지와 같은 정책).

---

## `source` 라벨 분기 — 이번 작업의 정직성 핵심 (P4 · C6)

판정을 화면의 `if`에 흩지 않고 **모델의 게터 하나**로 모았다. 화면이 늘어도 규칙이 갈라지지 않는다.

**`lib/models/briefing.dart:38`**
```dart
bool get isAiGenerated => source == 'AI' || source == 'CACHED_AI';
```

**`lib/screens/detail/spot_detail_screen.dart:607-608`**
```dart
if (briefing != null && briefing.isAiGenerated)
  Text('Gemini로 생성됨', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
```

| `source` | `isAiGenerated` | "Gemini로 생성됨" |
|---|---|---|
| `AI` | true | 표시 |
| `CACHED_AI` | true | 표시 |
| `TEMPLATE` | false | **미표시** |
| `NONE` | false | **미표시** |
| 모르는 값 (향후 폴백 단계) | false | **미표시** (안전한 기본값) |

로딩 중에는 `briefing == null`이라 라벨이 붙지 않는다 — 문장이 도착하기 전에 출처부터
주장하는 상태가 생기지 않는다.

검증: 계약서의 실측 JSON 5종(AI / CACHED_AI / TEMPLATE / NONE / 미지의 `STALE_CACHE`)을
`Briefing.fromJson`에 그대로 넣어 파싱·판정을 확인했다. 결과는 위 표와 일치.

---

## 3분기 렌더 상태 (Q6=A)

| 상태 | 조건 | 화면 |
|---|---|---|
| 로딩 | `_briefingLoading && _briefing == null` | 회색 스켈레톤 바 3줄 (`_buildBriefingSkeleton` `:623`) |
| 정상 | `_briefing != null` | 타이핑 애니메이션으로 `full_briefing` 출력 |
| 실패 | `!_briefingLoading && _briefing == null` | `SizedBox.shrink()` — 섹션 통째로 사라짐 (`:586`) |

**타이핑 트리거 변경**: "500ms 후 무조건 시작" → **"응답 도착 후 시작"**
(`_fetchBriefing` → `_startBriefingTyping(briefing.fullBriefing)` `:126`, `:135`).
캐시 미스 시 생성에 수 초가 걸려서, 예전 트리거는 빈 화면에 커서만 도는 상태였다.
`AnimationController`·`_charIndex` 등 기존 애니메이션 로직은 그대로 재사용했고 대상 문자열만
`_demoBriefing`(하드코딩) → `_briefingFullText`(서버 응답)로 바뀌었다.

---

## 수정/신규/삭제 파일

| 파일 | 변경 |
|---|---|
| `lib/models/briefing.dart` | **재작성.** `Briefing.fromJson` + `BriefingBasedOn` 신설, `isAiGenerated` 게터. 중복 `CrowdednessInfo` 클래스 **제거**(`congestion_info.dart`와 이름 충돌), 폐기 필드 `summaryLine`·`weather`·`crowdedness` 제거 |
| `lib/services/api_service.dart` | `fetchBriefing(contentId)` 신규 (`fetchWeather` 바로 아래). `import '../models/briefing.dart'` 추가 |
| `lib/screens/detail/spot_detail_screen.dart` | `_demoBriefing` 4문장 **삭제**, `_showFullBriefing` 삭제, `_fetchBriefing()`·`_startBriefingTyping()`·`_buildBriefingSkeleton()` 신규, `_buildAiBriefingSection()` 3분기 재작성, `'Gemini로 생성됨'` 조건부화, `initState`의 500ms `Future.delayed` 제거 |
| `lib/providers/briefing_provider.dart` | **삭제** (Q8=A). 삭제 전 grep으로 import 0건 재확인 |
| `lib/widgets/briefing_card.dart` | **변경 없음** (C7 — 범위 밖) |

### 스키마에서 사라진 것 — 앱에도 없음을 확인
`summary_line` · `weather` · `crowdedness`는 서버 응답에 없다. 모델에서 지웠고 화면에
요약 줄을 따로 만들지 않았다. 브리핑 섹션이 그리는 문장은 `full_briefing` **하나뿐**이다.

### `generated_at` 파싱
서버는 naive UTC(`"2026-09-06T15:35:47.050148"`, `Z` 없음)를 보낸다.
`Briefing._parseUtc`가 tz 접미사 유무를 검사해 없으면 `Z`를 붙여 파싱한다 —
안 붙이면 로컬 시각으로 오인해 9시간 어긋난다. 실측: `15:35:47Z` → `local 2026-09-07 00:35:47` (KST +9) ✅
(현재 화면에 "N분 전 생성"을 표기하지는 않는다. 필드는 확보해 뒀다.)

---

## 검증 결과

### `dart analyze`
```
73 issues found.  (전부 info/warning 레벨의 기존 지적)
```
- **이번 작업이 손댄 파일의 신규 지적 0건.**
  - `lib/models/briefing.dart` — 지적 0건
  - `lib/services/api_service.dart` — `avoid_print` 2건(`:70`, `:84`)만, 둘 다 기존 코드
  - `lib/screens/detail/spot_detail_screen.dart` — `withOpacity` deprecation 4건만, 전부 기존 코드
- 남은 73건은 저장소 전역의 기존 부채다: `withOpacity` deprecation 다수, `avoid_print`,
  `auth_service.dart`의 `firebase_auth` 미설치(error), `test/widget_test.dart`의 `MyApp` 미정의(error).
  전부 이번 작업 범위 밖이라 손대지 않았다.
- `flutter analyze`가 아니라 `dart analyze`를 쓴 것은 008 일지와 같은 이유다 —
  프로젝트 경로에 한글이 섞여 있어 analysis server가 죽는다.

### 실서버 curl 대조 — **미완 (환경 문제)**
```
GET http://127.0.0.1:8000/api/spots/126508/briefing  →  404 {"detail":"관광지를 찾을 수 없습니다."}
GET http://127.0.0.1:8000/api/spots/126508/weather   →  404 (동일)
```
브리핑 핸들러는 `tour_service.get_spot_detail()`이 비면 즉시 404를 낸다. 같은 content_id로
`/weather`도 404가 나는 것으로 보아 **라우팅·직렬화 문제가 아니라 TourAPI(`apis.data.go.kr`)
연결 불가**가 원인이다 — 계약서 65~71행이 경고한 그 상태 그대로다.

그래서 살아 있는 서버로 키를 대조하지 못했고, 대신 **계약서에 기록된 실측 응답 원문 5종을
`Briefing.fromJson`에 그대로 통과시켜** 키 1:1 대조를 마쳤다(전 케이스 파싱 성공, 라벨 판정 일치).
`app/models/schemas.py:116-131`의 `BriefingResponse`·`BriefingBasedOn` 필드명과도 직접 대조했다.

**TourAPI 복구 후 재검증이 필요하다.** 앱 구동 스모크(`flutter run`)는 지시대로 하지 않았다.

---

## 미해결 이슈

1. **실서버 스모크 미완** — TourAPI 연결 불가로 `/briefing`이 모든 content_id에서 404다.
   복구 후 ① 200 응답의 실제 키 ② `source`별 라벨 렌더 ③ 캐시 히트 시 타이핑 동작을 재확인해야 한다.
2. **"AI 브리핑" 섹션 배지 자체는 항상 표시된다** (`:600` 그라데이션 배지). `source=TEMPLATE`·`NONE`
   일 때 본문은 AI가 쓴 문장이 아닌데 섹션 제목은 여전히 "AI 브리핑"이다. 이번 지시는
   `'Gemini로 생성됨'` 라벨만 조건부화하라는 것이었고 섹션 명칭 변경은 범위 밖이라 두었으나,
   P4의 정직성 기준을 엄격히 적용하면 논의 대상이다. **판단 필요.**
3. **제보 직후 인플레이스 갱신 없음** — 제보 등록 후 `_showReportModal`은 `_fetchReports()`·
   `_fetchLiveStatus()`만 다시 부른다. 브리핑은 상세페이지를 **재진입**해야 갱신된다
   (서버 캐시 서명은 제보 1건에 바뀌므로 재진입이면 충분하다 — 01_spec 6절 검증 포인트 6도
   "재진입" 기준이다). 같은 화면에서 즉시 갱신되길 원하면 `_fetchBriefing()` 한 줄 추가로 되지만,
   Gemini 재호출 비용이 붙어서 임의로 넣지 않았다. **판단 필요.**
4. **`generated_at`을 화면에서 쓰지 않는다** — "N분 전 생성" 표기는 만들지 않았다(지시 범위 밖).
   캐시 히트 시 생성 시각이 유지되므로 필요해지면 바로 붙일 수 있다.
