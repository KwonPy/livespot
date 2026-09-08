# Flutter 연결표: Credit + 뱃지 (기능 4 · 11)

> 작성: 2026-09-08 / flutter-builder
> 기준 계약: `_workspace/02_backend_contract.md` (+ `01_spec.md` 2.3절 P21 · 2.4절 P25-P27)
> **실제 curl 응답으로 키를 대조 완료** 후, `02_backend_contract.md` 도착 시점에 재대조까지 마쳤다. 7절 참조.

---

## 1. 화면-엔드포인트 연결표

| 화면/위젯 | 호출 메서드 | 엔드포인트 | 읽는 JSON 키 | 에러 분기 |
|---|---|---|---|---|
| `profile_screen._buildStatsSection` (제보/답변 칸) | `fetchMyActivity` | `GET /api/credits/me/activity` | `report_count`, `answer_count` | ✅ 배너 + `-` |
| `profile_screen._buildStatsSection` (Credit 칸) | `fetchMyCredit` | `GET /api/credits/me` | `balance` | ✅ 배너 + `-` |
| `profile_screen._buildBadgeItem` (뱃지 칸) | `fetchMyCredit` | `GET /api/credits/me` | `badge.emoji`, `badge.label` | ✅ 배너 + `-` |
| `credit_ledger_screen._buildSummaryCard` | `fetchMyCredit` | `GET /api/credits/me` | `balance`, `total_earned`, `badge.emoji`, `badge.label`, `badge.next_label`, `badge.remaining` | ✅ 배너 |
| `credit_ledger_screen._buildLedgerList` | `fetchMyLedger(limit: 100)` | `GET /api/credits/me/ledger?limit=` | `id`, `amount`, `reason`, `created_at` | ✅ 배너 / 빈 상태 분리 |
| `credit_badge.CreditBadgeChip` | (없음 — 값을 주입받는 순수 표시 위젯) | — | `badge.emoji`, `badge.label` | — |

**파싱은 하지만 화면에 아직 안 쓰는 키** (계약 준수 목적으로 모델에는 있음):
`user_id`, `nickname`(로그인 단계에서 프로필 카드 '로그인하세요' 대체 예정), `badge.code`(QA 대조용), `badge.min_credit`, `badge.next_at`, `source_type`, `source_id`, `question_count`.

---

## 2. 실제 curl 응답 ↔ `fromJson` 대조 (문자 단위)

### `GET /api/credits/me` → `models/credit_summary.dart`

```json
{"user_id":"00000000-...-0001","nickname":"테스트유저","balance":120,"total_earned":120,
 "badge":{"code":"EXPLORER","label":"Spot 탐험가","emoji":"🧭","min_credit":100,
          "next_label":"베테랑","next_at":200,"remaining":80}}
```

| JSON 키 | Dart 필드 | 타입 | 확인 |
|---|---|---|---|
| `user_id` | `userId` | `String` | ✅ |
| `nickname` | `nickname` | `String` (non-null) | ✅ 서버가 사용자 행이 없어도 `"게스트"`로 채운다 (`services/credit.py:225`) |
| `balance` | `balance` | `int` | ✅ |
| `total_earned` | `totalEarned` | `int` | ✅ 뱃지 판정 기준(P5). 잔액과 구분해 받는다 |
| `badge.code` | `badge.code` | `String` | ✅ |
| `badge.label` | `badge.label` | `String` | ✅ 화면에 그대로 출력 |
| `badge.emoji` | `badge.emoji` | `String` | ✅ 화면에 그대로 출력 |
| `badge.min_credit` | `badge.minCredit` | `int` | ✅ |
| `badge.next_label` | `badge.nextLabel` | `String?` | ✅ 최상위(MASTER)에서만 null |
| `badge.next_at` | `badge.nextAt` | `int?` | ✅ 최상위에서만 null |
| `badge.remaining` | `badge.remaining` | `int?` | ✅ 최상위에서만 null |

### `GET /api/credits/me/ledger?limit=` → `models/credit_ledger_entry.dart`

```json
[{"id":"1412312d-...","amount":10,"reason":"REPORT","source_type":"report",
  "source_id":"eb452231-...","created_at":"2026-09-08T03:32:54.932734"}]
```

| JSON 키 | Dart 필드 | 타입 | 확인 |
|---|---|---|---|
| `id` | `id` | `String` | ✅ |
| `amount` | `amount` | `int` | ✅ **부호 유지** — 회수는 음수 행이라 절댓값으로 뭉개지 않는다 |
| `reason` | `reason` | `String` | ✅ `REPORT`/`ANSWER` |
| `source_type` | `sourceType` | `String` | ✅ |
| `source_id` | `sourceId` | `String` (non-null) | ✅ 답변 적립이면 question_id (질문당 1회 정책) |
| `created_at` | `createdAt` | `DateTime` | ✅ **naive UTC** — `_parseUtc`가 `Z`를 붙여 파싱. 안 붙이면 9시간 어긋난다 |

### `GET /api/credits/me/activity` → `models/activity_counts.dart`

```json
{"report_count":17,"answer_count":0,"question_count":4}
```

| JSON 키 | Dart 필드 | 타입 | 확인 |
|---|---|---|---|
| `report_count` | `reportCount` | `int` | ✅ |
| `answer_count` | `answerCount` | `int` | ✅ |
| `question_count` | `questionCount` | `int` | ✅ (모델에만 있고 화면 미사용) |

### 검증한 경계 케이스

| 케이스 | 확인 방법 | 결과 |
|---|---|---|
| 빈 상태 (P23) | `X-Test-User-Id: seed_user_30` | `200` + `balance:0`, `total_earned:0`, `SPROUT` 뱃지, ledger `[]` → **에러가 아니라 빈 상태 UI로 렌더**됨 |
| 최상위 등급 | `services/credit.py:74-75` | `next_label`/`next_at`/`remaining` **셋 다 null** → `CreditBadge.isMax`가 `nextLabel == null`로 판정, "최고 등급이에요" 출력 |
| 사용자 전환 | 드롭다운 → `X-Test-User-Id` 헤더 | 크레딧이 사용자별로 갈림 확인. 전환 시 `_reloadStats()`로 재조회 |

---

## 3. 위젯 트리 요약

### `ProfileScreen`

`isActive`가 false→true로 바뀌면 `didUpdateWidget`이 `_statsFuture`를 새로 만든다 (7절 참조).

```
Scaffold > SafeArea > SingleChildScrollView > Column
├─ _buildProfileCard()                       파란 그라데이션 카드
│  └─ Row [카카오 로그인]                     ← Google 버튼 제거 (function.md:76 "카카오 하나만")
├─ _buildStatsSection()
│  └─ FutureBuilder<_MyStats>                 fetchMyCredit + fetchMyActivity를 Future.wait
│     ├─ waiting → 회색 스켈레톤 박스 4개      (0을 그리지 않는다)
│     ├─ hasError → 스탯 전부 '-' + 빨간 배너(원문 메시지 + '다시 시도')
│     └─ data → Row
│        ├─ 제보  activity.report_count
│        ├─ 답변  activity.answer_count
│        ├─ Credit credit.balance + 'p'
│        └─ 뱃지  CreditBadgeChip(credit.badge)   ← 죽어있던 '북마크' 자리를 대체
├─ _buildTestUserSwitcher()                   kDebugMode 전용. **그대로 유지, 손대지 않음**
└─ _buildMenuSection()
   └─ 'Credit 내역' → Navigator.push(CreditLedgerScreen)   ← 유일하게 연결된 메뉴
      (나머지 7개는 onTap: null → 리플조차 없어 "죽은 메뉴"임이 드러난다)
```

### `CreditLedgerScreen`

```
Scaffold > AppBar('Credit 내역') > RefreshIndicator > ListView
├─ _buildSummaryCard()   FutureBuilder<CreditSummary>
│  ├─ waiting → CircularProgressIndicator
│  ├─ hasError → 빨간 배너 (원문 메시지)
│  └─ data → 파란 카드 [balance 'p' | CreditBadgeChip(onDark)]
│                      누적 적립 {total_earned}p
│                      "다음 등급 {next_label}까지 {remaining}p" | "최고 등급이에요"
└─ _buildLedgerList()    FutureBuilder<List<CreditLedgerEntry>>
   ├─ waiting → CircularProgressIndicator
   ├─ hasError → 빨간 배너 (원문 메시지)
   ├─ isEmpty  → 회색 '아직 적립 내역이 없어요'      ← 에러와 명확히 다른 화면
   └─ data → ListTile 목록
      leading  reason별 아이콘
      title    reasonLabel(reason)  '현장 제보' / 'Q&A 답변' / (모르는 코드는 원문 그대로)
      subtitle Formatters.reportRecency(created_at)
      trailing '+10p' (녹색) / 음수는 빨강
```

---

## 4. 설계 원칙 준수 확인

| 규칙 | 어떻게 지켰나 |
|---|---|
| **P22/P27 — 앱은 등급을 판정하지 않는다** | Dart 어디에도 등급 컷(0/50/100/200/500)·라벨·이모지 상수가 **없다**. `constants.dart` 무수정. `grep -rn "새싹\|탐방객\|탐험가\|베테랑\|마스터\|SPROUT\|VETERAN" lib/` → **코드 0건** (유일한 hit은 `credit_summary.dart:50`의 주석 안 예시 문구) |
| **`next_at - total_earned` 재계산 금지** | 서버가 준 `remaining`을 그대로 출력. 진행바를 넣지 않은 이유도 이것 — 비율을 그리려면 앱이 산수를 하게 된다 |
| **P25 — 하드코딩 `'0'`·`'0p'` 제거** | `profile_screen.dart`에 리터럴 스탯 값이 남아 있지 않다 |
| **P26 — 실패 시 0을 그리지 않는다** | 값 파라미터가 `String?`이고, null이면 로딩=스켈레톤 / 실패=`'-'`. `?? 0` 형태의 폴백이 없다 |
| **에러 ≠ 빈 상태** | 원장 화면에서 `hasError`(빨간 배너)와 `isEmpty`(회색 안내)가 완전히 다른 위젯 |
| **조회 실패는 예외로 전파** | 세 메서드 모두 non-200에 `throw`. 빈 리스트로 삼키지 않는다 (`fetchTestUsers`가 404를 빈 목록으로 처리하는 것과 의도적으로 다르다) |
| **`future`를 build에서 만들지 않는다** | 양쪽 화면 모두 `initState`에서 생성, 재조회는 `setState`로 명시적 교체 |
| **테스트유저 드롭다운 불간섭** | `_buildTestUserSwitcher()` 원문 유지. `_onSelectTestUser`에 `_reloadStats()` 한 줄만 추가 |

---

## 5. 변경/신규 파일

| 파일 | 상태 |
|---|---|
| `lib/models/credit_summary.dart` | 신규 — `CreditSummary` + `CreditBadge` |
| `lib/models/credit_ledger_entry.dart` | 신규 — `reasonLabel()` 포함 |
| `lib/models/activity_counts.dart` | 신규 (계약 P21 ③를 타입으로 고정하려고 추가) |
| `lib/widgets/credit_badge.dart` | 신규 — `CreditBadgeChip` (표시 전용 pill) |
| `lib/screens/profile/credit_ledger_screen.dart` | 신규 — Credit 내역 화면 |
| `lib/services/api_service.dart` | `fetchMyCredit` / `fetchMyLedger` / `fetchMyActivity` 추가 |
| `lib/screens/profile/profile_screen.dart` | 스탯 실값 연결, 뱃지 칸 교체, 내역 화면 연결, Google 버튼 제거, `isActive` 재조회 |
| `lib/screens/home/home_screen.dart` | `ProfileScreen`에 `isActive` 전달 (7절 stale 크레딧 수정) |
| `lib/config/constants.dart` | **무수정** (앱에 둘 상수가 없다) |

`flutter analyze`: **73 issues — 작업 전 baseline과 동일, 신규 파일 지적 0건.**
남은 73건은 전부 기존 코드의 `withOpacity` deprecation(60여 건) + 선재하는 error 2건
(`auth_service.dart`의 `firebase_auth` 미설치, `test/widget_test.dart`의 `MyApp` 부재)이며 이번 범위 밖이다.

---

## 6. 백엔드에 남기는 메모 (요청 아님, 관찰)

- `reason` 코드의 한국어 표시 문구만 서버가 안 내려준다. 지금은 `CreditLedgerEntry.reasonLabel()`이 매핑하고 **모르는 코드는 코드 원문을 그대로 표시**한다. 나중에 사유가 늘면(이벤트/회수 등) 서버가 `reason_label`을 함께 내려주는 편이 안전하다.
- `question_count`는 받아만 두고 화면에 쓰지 않는다 — 스탯 칸이 4개뿐이고 질문은 0점 정책이라 뱃지 칸에 밀렸다.

---

## 7. `02_backend_contract.md` 재대조 (도착 후)

계약서가 지목한 3가지를 코드에서 확인했다. **3건 모두 이미 부합했고 수정이 필요 없었다** — P21을 계약으로 삼아 작성했고, 서버 기동 중에 실측 curl로 한 차례 대조했기 때문이다.

| # | 계약서 지적 | 내 코드 | 상태 |
|---|---|---|---|
| 1 | `badge.next_label`/`next_at`/`remaining`은 nullable, MASTER에서만 null. non-null 캐스팅 금지 | `credit_summary.dart:87-89` → `as String?` / `as int?` / `as int?`. 생성자도 `required` 아님. `isMax`가 `nextLabel == null`로만 판정 | ✅ 부합 |
| 2 | `/ledger`는 최상위가 배열 (`{items:[...]}` 아님) | `api_service.dart:341` → `final List<dynamic> data = response.data;` 로 바로 캐스팅. 래퍼를 가정한 코드 없음 (Dio가 이미 디코드하므로 `jsonDecode` 불필요) | ✅ 부합 |
| 3 | `report_count`/`answer_count`로 크레딧 역산 금지 | activity 값의 사용처는 `profile_screen.dart:248,257` 두 곳뿐이고 **건수를 그대로 출력**만 한다. Credit 칸은 `credit.balance`, 원장 화면 헤더는 `total_earned`를 그대로 쓴다. 곱셈·덧셈 없음 | ✅ 부합 |

계약서에서 추가로 확인한 것:

| 항목 | 확인 |
|---|---|
| `limit` 범위 1~100 (밖이면 422) | 원장 화면이 `limit: 100`을 보낸다 — 상한 경계값이라 유효 |
| `badge.code` 5개 값 | 앱이 `code`로 분기하는 곳 **없음**. 파싱만 하고 화면엔 label/emoji만 쓴다 |
| `source_type`은 `answer`인데 `source_id`는 question.id | 모델 주석에 명시. 화면은 `source_id`를 쓰지 않으므로 오해 여지 없음 |
| 적립은 제보/답변 응답에 드러나지 않는다 (계약 4절) | ⚠️ **아래 수정 1건 발생** |

### 이 재대조에서 발견해 고친 것 — 마이 탭의 stale 크레딧

계약 4절이 *"앱이 '적립됐는지'를 알고 싶으면 제보/답변 성공 후 `/api/credits/me`를 다시 불러 비교해야 한다"*고 명시한다. 그런데 `home_screen.dart:125`가 **`IndexedStack`**이라 탭이 살아 있고, `ProfileScreen.initState`는 앱 실행 중 **한 번만** 돈다.

→ 제보해서 크레딧이 +10 되어도 **마이 탭으로 돌아오면 예전 숫자가 그대로 보인다.** "제보했는데 크레딧이 안 올라요"로 신고될 증상이고, 원인은 서버가 아니라 앱이다.

**수정**: `MapScreen`이 이미 쓰고 있던 `isActive` 규약을 그대로 따랐다(새 패턴을 만들지 않았다).

| 파일 | 변경 |
|---|---|
| `home_screen.dart:24,119` | `_profileTabIndex = 2` 추가, `ProfileScreen(isActive: _currentIndex == _profileTabIndex)` |
| `profile_screen.dart` | `isActive` 필드(기본 `true`) + `didUpdateWidget`에서 비활성→활성 전환 시 재조회 |

재조회 경로는 이제 4개다: ① 최초 진입 ② **마이 탭 재진입** ③ 테스트유저 전환 ④ Credit 내역 화면에서 복귀. 추가로 에러 배너의 '다시 시도' 버튼.

### 미검증으로 남긴 것 (정직하게)

- **MASTER 등급 렌더링**: `next_*` 3개가 null일 때 "최고 등급이에요"가 나오는 경로를 실데이터로 보지 못했다. 500크레딧 사용자가 없기 때문이다. 코드 검사(`isMax`)와 계약서 1절 실측표(`total_earned=500` → null 3개)로만 확인했다. 시드 백필이 이뤄지면 실물 확인 가능.
- **재대조 시점에 서버가 내려가 있어** 이번 라운드의 curl 재확인은 하지 않았다. 앞선 라운드에서 엔드포인트 3개 전부 + 빈 상태(`seed_user_30`) + 사용자 전환을 실측했고, 계약서의 응답 원문이 그 실측과 일치한다.
