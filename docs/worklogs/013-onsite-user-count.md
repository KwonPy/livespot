# 현장 사용자 수 집계 (기능 6)

작업일: 2026-09-09

## 1. 한 줄 요약

관광지 근처에서 GPS 인증을 한 사람을 "현장 사용자"로 기록해 두고, **"최근 30분 기준 N명"**을 상세페이지와 Live 페이지에 보여준다. 덤으로 현장에 있는 사람에게 "지금 답변을 기다리는 질문"을 배너로 띄운다.

---

## 2. 왜 만들었는가

이 앱의 핵심은 "지금 그 자리에 있는 사람이 지금의 상황을 알려준다"는 것이다. 그런데 지금까지는 **누가 그 자리에 있는지를 서버가 전혀 모르고 있었다.**

그래서 두 가지가 막혀 있었다.

1. **"이 관광지에 지금 사람이 있나?"를 보여줄 수 없었다.** LIVE 상태창에는 "제보 N건"만 있었고, 코드 주석에도 "현장 인원은 아직 실제 데이터가 없어 표시하지 않는다"고 자리만 비워둔 상태였다 ([005](005-live-status-hotspots.md) 12절이 "기능 6이 붙으면 `LiveStatusResponse`에 현장 인원 필드를 추가"라고 미리 지정해 뒀다).
2. **질문이 올라와도 답해 줄 사람에게 알릴 방법이 없었다.** 앞으로 만들 기능 8(질문 푸시 알림)의 "누구에게 보낼 것인가"는 결국 **"이 관광지에 최근 30분 안에 있었던 사람들"**이다. 그 명단을 만드는 재료가 이번 기능이다.

즉 이번 기능은 **화면에 숫자 하나를 띄우는 일**인 동시에 **기능 8의 선행 공사**다. 지금 스키마를 잘못 잡으면 기능 8에서 되돌려야 한다.

세 번째로, `function.md`가 웹의 한계를 이미 인정하고 있다 — "웹 푸시는 도달률이 낮다. **위치 신호 응답에 대기 질문을 실어 보내는 것이 사실상 주 전달 경로다.**" 그래서 이번에 배너까지 같이 만들었다.

---

## 3. 구현한 것

### 신규 API는 0개다

가장 중요한 결정이라 먼저 적는다. **위치 신호를 보내는 새 엔드포인트도, 새 타이머도 만들지 않았다.** 이미 있는 `POST /api/reports/verify-location`(GPS 현장 인증)이 성공하면 서버가 그 김에 현장 기록을 남긴다. 자세한 이유는 9절.

### 백엔드

- **새 테이블 `presences`** — "누가 · 어느 관광지 근처에 · 마지막으로 언제 있었는지" 딱 한 줄. 마이그레이션 1건(`c924ebb93d39`).
  - 좌표(`lat`/`lng`) 컬럼이 **아예 없다.** 관광지까지의 거리(`distance_m`)만 남긴다.
  - `UNIQUE(user_id, spot_content_id)` — 같은 사람·같은 관광지는 영원히 한 줄이고 `last_seen`만 덮어쓴다.
- **`app/services/presence.py` 신규** — 현장 사용자 판정을 한 곳에 모은 모듈.
  - `record_presence()` — 위치 신호 1건 처리(24시간 지난 행 파기 + 내 행 갱신을 한 트랜잭션으로)
  - `count_onsite_users()` — 최근 30분 인원 수 (이번 화면이 씀)
  - `get_onsite_user_ids()` — 최근 30분 사용자 id 목록 (**기능 8이 그대로 쓸 함수. 지금은 아무도 안 부른다**)
- **`POST /api/reports/verify-location` 응답 확장** — `presence_registered`(bool), `pending_questions`(배열) 추가
- **`GET /api/live/status/{content_id}` 응답 확장** — `onsite_user_count`(int) 추가
- **`app/services/question_query.py` 신규** — `questions.py`에 있던 "답변 대기 질문 조회" 로직을 빼내 두 곳(기존 Q&A 목록 API, 새 위치 신호 응답)이 같은 함수를 쓰게 했다
- 설정값 3개: `PRESENCE_WINDOW_MINUTES=30`, `PRESENCE_RETENTION_HOURS=24`, `PRESENCE_PENDING_QUESTION_LIMIT=5`

### 프론트

- 상세페이지 **진입 시 위치 신호 1회 자동 전송** (기존에는 "현장 제보" 버튼을 눌러야만 나갔다)
- 상세페이지 LIVE 상태창에 **"현장 N명 / 최근 30분 기준"** 칸 추가
- Live 페이지 "내 현장" 헤더에 **"지금 여기 N명 · 최근 30분 기준"** 추가
- **답변 대기 질문 배너**(`pending_questions_banner.dart`) 신규 — 두 화면 공통, 탭하면 기존 답변 모달이 열린다
- `qa_section.dart`의 `FutureBuilder`에 `hasError` 분기 추가 (기존에 빠져 있던 것)
- 모델 파싱 회귀 테스트 `test/presence_contract_test.dart` 신규 — 백엔드에서 실제로 받은 응답 원문을 그대로 넣었다

`api_service.dart`는 **한 줄도 안 고쳤다.** 새 엔드포인트가 없으니 새 호출 메서드도 없다.

---

## 4. 동작 흐름

### (A) 위치 신호가 기록되기까지

```
상세페이지 진입 (또는 Live 화면의 기존 3분 타이머)
→ LocationService.getCurrentPosition()  — 브라우저에서 내 좌표 얻기
→ ApiService.verifyLocation(contentId, lat, lng)
→ POST /api/reports/verify-location
→ 서버: TourAPI로 그 관광지의 좌표를 조회
→ 서버: calculate_distance_m()으로 거리 계산 → 150m 이내인가?
   ├─ 밖 → presences에 아무것도 안 씀. 응답은 200 + presence_registered:false
   └─ 안 → services/presence.py::record_presence()
            ① 24시간 지난 남의 행들 DELETE
            ② 내 행 UPSERT (있으면 last_seen만 갱신 / 없으면 INSERT)
            ③ commit
→ 응답: {verified, distance_m, threshold_m, message,
         presence_registered, pending_questions[]}
   ※ lat/lng는 여기서 버려진다. DB에 안 들어간다.
→ 앱: presence_registered가 true면 pending_questions를 배너에 담는다
```

### (B) "현장 N명"이 화면에 뜨기까지

```
화면이 GET /api/live/status/{content_id} 호출
→ 서버: count_onsite_users(db, content_id)
        SELECT COUNT(DISTINCT user_id) FROM presences
        WHERE spot_content_id = ? AND last_seen >= (지금 - 30분)
                                     ↑ 여기가 전부다. 접속 여부를 안 본다
→ 응답에 "onsite_user_count": 1
→ Dart LiveStatus.fromJson: json['onsite_user_count'] as int
→ 화면: "현장 1명 / 최근 30분 기준"
```

**중요한 점**: 만료를 처리하는 코드가 어디에도 없다. "30분이 지났다"고 표시를 바꾸는 배치도, `is_active` 같은 컬럼도 없다. **조회할 때마다 시각을 비교할 뿐**이라 아무것도 안 해도 30분 뒤 저절로 인원에서 빠진다.

---

## 5. 주요 파일

### 백엔드

| 파일 | 역할 |
|---|---|
| `app/db/models/presence.py` | **신규.** `presences` 테이블 정의. 주석에 "스키마가 곧 프라이버시 정책"인 이유를 적어뒀다 |
| `app/services/presence.py` | **신규.** 기록(`record_presence`/`touch_presence`) · 파기(`purge_expired_presence`) · 집계(`count_onsite_users`/`get_onsite_user_ids`) |
| `app/services/question_query.py` | **신규.** 질문 조회·조립 로직을 `questions.py`에서 빼낸 것. 두 API가 공유 |
| `app/services/report_window.py` | `presence_window_cutoff_utc()`(30분) · `presence_retention_cutoff_utc()`(24시간) 추가. 시간 계산은 전부 이 파일에 모은다 |
| `app/api/reports.py` | `verify_location`이 DB 세션·사용자 id를 받게 되고, 인증 성공 시 presence 기록 + 대기 질문 동봉 |
| `app/api/live.py` | `get_live_status`가 `count_onsite_users`를 불러 인원을 합류시킴 |
| `app/models/schemas.py` | `VerifyLocationResponse` +2필드 / `LiveStatusResponse` +`onsite_user_count` |
| `migrations/versions/c924ebb93d39_add_presences_table.py` | **신규.** 테이블 생성만 (기존 테이블 `ALTER` 없음 → SQLite·Postgres 양쪽에서 동일하게 돈다) |

### 프론트

| 파일 | 역할 |
|---|---|
| `lib/models/verify_location_result.dart` | 서버 응답에 `presenceRegistered` · `pendingQuestions` 추가 |
| `lib/models/live_status.dart` | `onsiteUserCount` 추가 |
| `lib/widgets/pending_questions_banner.dart` | **신규.** 답변 대기 질문 배너 |
| `lib/screens/detail/spot_detail_screen.dart` | 진입 시 신호 1회(`_sendPresenceSignal`) · "현장" 칸 · 배너 |
| `lib/screens/live/live_screen.dart` | "지금 여기 N명" · 배너 · `_fetchOnsiteCount` |
| `lib/widgets/qa_section.dart` | `hasError` 분기 추가 |
| `lib/config/constants.dart` | `presenceWindowMinutes = 30` (화면 문구용. 판정은 서버가 한다) |
| `test/presence_contract_test.dart` | **신규.** 실측 응답 원문으로 3개 모델 파싱 검증 |
| `lib/screens/profile/profile_screen.dart` | **이번 기능과 무관하지만 함께 수정.** `_reloadStats()`의 `setState(() => _statsFuture = _loadStats())`가 대입식의 값(Future)을 반환해 "setState() callback argument returned a Future"로 크래시하던 기존 버그. 블록 본문으로 교체(8-4 참고) |

---

## 6. 핵심 코드 / 개념

### 6-1. "상태를 저장하지 말고 계산하라"

이 프로젝트가 계속 지켜온 방식이다. 질문의 TTL 2시간도, 하루 단위 리셋도 전부 이렇게 한다.

**나쁜 방법**: `presences` 테이블에 `is_onsite` 같은 칸을 두고, 30분마다 도는 프로그램이 그 칸을 `false`로 바꾼다.
→ 그 프로그램이 5분 늦으면 **DB가 거짓말을 한다.** 죽으면 영원히 거짓말한다.

**쓴 방법**: 칸을 안 두고, 물어볼 때 계산한다.

```python
select(func.count(func.distinct(Presence.user_id))).where(
    Presence.spot_content_id == spot_content_id,
    Presence.last_seen >= presence_window_cutoff_utc(),   # 지금 - 30분
)
```

→ 항상 정확하다. 늦을 수가 없다. 관리할 배치도 없다.

QA에서 이게 실제로 그렇게 도는지 직접 확인했다. `seed_user_01`의 행이 **DB에 그대로 남아 있는데도** 인원 집계에서는 빠져 있었다(마지막 신호가 50분 전이라서). 행을 지운 게 아니라 계산에서 제외된 것이다.

### 6-2. 좌표를 안 남기는 이유 — 코드가 아니라 스키마로 막았다

"좌표를 저장하지 않겠다"는 약속을 **`if` 문으로 지키면 언젠가 새어나간다.** 그래서 테이블에 `lat`/`lng` 칸 자체를 만들지 않았다.

```sql
CREATE TABLE presences (
    id, user_id, spot_content_id, last_seen, distance_m   -- 좌표 칸이 없다
)
```

같은 이유로 **방문 이력을 쌓지 않는다.** 한 사람·한 관광지당 한 줄을 계속 덮어쓴다. 만약 신호마다 새 줄을 추가했다면 3분 주기 × 하루 = **1인당 480줄의 이동 경로**가 DB에 남았을 것이다. 지금 구조에서는 "이 사람이 오늘 어디를 다녔나"를 물어볼 방법이 원리적으로 없다.

### 6-3. 반경 밖인데 왜 에러(403)가 아니라 200인가

위치 신호는 **사용자가 누른 적 없는 배경 동작**이다. 상세페이지에 들어가기만 해도 조용히 나간다.

여기서 "반경 밖 = 403 에러"로 만들면, 집에서 앱을 구경하던 사용자에게 **"오류가 발생했습니다"가 뜬다.** 하지만 그건 오류가 아니라 지극히 정상적인 상황이다(집은 관광지가 아니니까).

그래서 반경 밖이어도 **200 + `presence_registered: false`**를 준다. 앱은 이걸 보고 아무것도 하지 않는다.

```dart
if (!result.presenceRegistered) return;   // 조용히 끝
...
} catch (_) {
  // 신호 실패는 알리지 않는다. 현장 인원에 내가 안 잡힐 뿐이다.
}
```

**다만 "현장 제보하기" 버튼을 눌렀을 때는 기존대로 에러 메시지를 보여준다.** 그건 사용자가 명시적으로 시킨 행동이라 실패를 숨기면 안 된다. 두 경로를 서로 다른 메서드로 완전히 분리해 뒀다(`_sendPresenceSignal` vs `_attemptOnsiteVerification`).

### 6-4. 배너를 `if`가 아니라 데이터로 막았다

"현장에 없는 사람에게 답변 버튼이 보이면 안 된다"를 지키는 방법이 두 가지 있다.

- (A) 배너 위젯에 `if (인증됨)` 조건을 건다 → 조건이 하나 바뀌면 새어나온다
- (B) **인증 안 된 사람은 애초에 그릴 목록을 갖지 못하게 한다** ← 이걸 택함

```dart
if (!result.presenceRegistered) return;                 // 목록을 안 담는다
setState(() => _pendingQuestions = result.pendingQuestions);
```

빈 목록이면 배너는 `SizedBox.shrink()`로 접힌다. 게다가 서버도 반경 밖이면 `pending_questions: []`를 주므로 **이중으로 막혀 있다.** 이 방식은 [006](006-realtime-qna.md)에서 "전체 LIVE Q&A에서는 답변 불가"를 지킬 때 쓴 것과 같은 원리다.

### 6-5. 시간창이 다른 숫자를 한 줄에 두지 않는다

LIVE 상태창에는 이제 성격이 다른 두 숫자가 나란히 있다.

| 칸 | 숫자 | 시간창 |
|---|---|---|
| 제보 | 0건 | 최근 **2시간** |
| 현장 | 1명 | 최근 **30분** |

원래 헤더 오른쪽에 "최근 2시간 기준"이라는 문구가 하나 붙어 있었는데, 이대로 두면 그 한 문장이 **두 숫자를 다 대표하는 것처럼 보인다.** 그래서 헤더 문구를 제거하고 **칸마다 기준을 따로** 적었다.

문구도 "현재 N명"이 아니라 **"최근 30분 기준 N명"**이다. 웹은 탭을 닫으면 즉시 끊기므로 "현재 접속자"를 우리가 알 방법이 없다. 모르는 것을 아는 척하지 않는다.

---

## 7. 사용한 기술

새 라이브러리·외부 API는 **0개**다. 이번 기능은 전부 이미 있는 것으로 만들었다.

| 기술/개념 | 어디에 |
|---|---|
| SQLAlchemy `UniqueConstraint` + UPSERT (SELECT → UPDATE/INSERT) | `presences` 1행 유지. `ON CONFLICT` 구문은 DB마다 달라서 안 씀 |
| `IntegrityError` 폴백 | 같은 사용자의 신호 2건이 동시에 오면 UNIQUE 제약이 막고, 잡아서 UPDATE로 합류 |
| Alembic 마이그레이션 (신규 테이블만) | SQLite(로컬)·Postgres(Railway) 양쪽 호환 |
| `func.count(func.distinct(...))` | 사용자 단위 중복 제거 |
| naive UTC datetime 규약 | 서버는 `datetime.utcnow()`, Dart는 `_parseUtc`로 `Z`를 붙여 파싱 |
| Pydantic 전방 참조 + `model_rebuild()` | `VerifyLocationResponse`가 `QuestionResponse`를 문자열로 참조 |

---

## 8. 문제와 해결

### 8-1. 설계서가 자기 자신과 모순됐다

- **문제**: `function.md` 기능 6이 **같은 절 안에서 두 가지 설계를 말했다.** 첫 문단은 "현장 **제보 작성 시점에** 현장 활동으로 인정", 불릿은 "앱은 좌표만 보내고… **아무 관광지도 열지 않아도 자동 참여**".
- **원인**: 설계 시점 문서라 세부를 확정하지 않은 채 두 아이디어가 같이 남아 있었다. 우선순위 규칙(사용자 정책 > 일지 > 코드 > 설계서)으로도 해소가 안 된다 — **한 문서 안에서 갈리기 때문**이다.
- **해결**: 판정하지 않고 사용자에게 선택지 3개(제보에 얹기 / 독립 채널 신설 / 기존 GPS 인증에 얹기)를 대가와 함께 올렸다. 사용자가 3번을 택했다. 9절 참조.
- **배운 점**: **한 문서 안에서 갈리는 모순은 우선순위 규칙으로 못 푼다 — 사용자에게 올려야 한다.** 이 판정 기준은 `spec-arbiter`가 이미 갖고 있어(문서 간 충돌표) 따로 규칙을 추가하지 않았다.

### 8-2. 같은 판정을 두 곳이 각자 짜면 어긋난다

- **문제**: "이 관광지의 현장 사용자는 누구인가"를 (a) 지금 만드는 인원 표시와 (b) 앞으로 만들 기능 8의 푸시 대상이 각각 물어보게 된다.
- **원인**: 라우터마다 쿼리를 직접 쓰면 조건이 조금씩 갈린다. 그러면 **"화면에는 3명이라고 떠 있는데 알림은 1명에게만 가는"** 상태가 되는데, 이건 테스트로 안 잡힌다 — 양쪽 다 각자는 맞기 때문이다.
- **해결**: 판정을 `services/presence.py`의 `count_onsite_users` / `get_onsite_user_ids` 두 함수로 뺐다. **둘의 WHERE 절이 문자 단위로 같고**, cutoff도 `report_window.py` 한 곳에서 가져온다. 기능 8은 `get_onsite_user_ids()`만 부르면 된다.
- **배운 점**: 두 번째 소비자가 아직 없어도 미리 함수로 뺀다. **이 규칙을 `livespot-backend` 스킬에 "같은 판정을 두 곳이 쓰면 라우터가 아니라 서비스에 둔다" 항목으로 추가했다.**

### 8-3. 성공 경로에서만 목록을 갱신하면 낡은 화면이 남는다 (QA가 잡음, 미수정)

- **문제**: `spot_detail_screen.dart:112`의 `if (!result.presenceRegistered) return;`는 **성공했을 때만** 배너 목록을 갈아끼운다. 그래서 답변 직후 재신호가 실패하면(반경 이탈·네트워크) 이미 답변한 질문이 배너에 그대로 남는다.
- **원인**: 같은 메서드(`_sendPresenceSignal`)가 "진입 시 최초 조회"와 "답변 후 갱신(`onAnswered` 콜백)" 두 용도로 쓰인다. 최초 조회에서는 이전 목록이 비어 있어 증상이 없다 — **두 번째 용도에서만 드러난다.**
- **해결**: **이번엔 안 고쳤다.** 데이터 오염이 아니라 화면 갱신 지연이고(답변 제출은 서버가 매번 GPS를 재검증하므로 반경 밖이면 서버가 거부한다), 재현 구간도 좁다. 11절에 남겨 다음 작업으로 넘긴다.
- **배운 점**: `live_screen.dart:133`은 이미 `verify.presenceRegistered ? verify.pendingQuestions : []`로 실패 시 빈 목록을 명시 대입해 이 경로가 없다. **같은 응답을 소비하는 화면이 둘인데 실패 처리 방식이 달랐다.** 이 교훈을 `bug-patterns.md`에 **"1-4. 성공 경로에서만 상태를 갱신해 실패 시 낡은 목록이 남음"** 항목으로 추가했다 — 검증 기준은 "같은 응답을 쓰는 화면이 둘 이상이면 실패 경로를 나란히 놓고 대조한다".

### 8-4. 마이 화면 "테스트유저 전환"이 크래시해 다인원 시나리오를 앱 안에서 재현할 수 없었다

- **문제**: 로그인이 없어 사용자가 사실상 1명(`test_user`)뿐이라, 이 기능(현장 인원 2명 이상)을 앱 화면에서 눈으로 보려면 마이 화면의 "테스트유저 전환" 드롭다운이 유일한 수단이다. 그런데 실제로 눌러보니 `profile_screen.dart:76` `_reloadStats()`에서 `DartError: setState() callback argument returned a Future`로 즉시 크래시했다.
- **원인**: `setState(() => _statsFuture = _loadStats())` — 화살표 본문은 마지막 식의 **값**을 그대로 반환한다. 대입식 `_statsFuture = _loadStats()`의 값은 `Future<_MyStats>`이고, 이게 `setState`의 콜백 반환값이 되어 Flutter가 예외를 던진다. 이번 기능과 무관한 기존 버그이고, 지금까지 아무도 그 드롭다운을 실제로 눌러보지 않아 드러나지 않았다.
- **해결**: 블록 본문(`setState(() { _statsFuture = _loadStats(); })`)으로 교체했다. `dart analyze` 재확인 결과 새 issue 없음(기존 `withOpacity` deprecated info 5건만 잔존).
- **배운 점**: **QA 시나리오 자체가 앱의 죽은 경로를 밟고서야 드러나는 버그가 있다.** "여러 사용자 시연은 테스트유저 전환으로만 가능하다"는 이번 일지·`03_flutter_wiring.md`에 이미 적힌 전제였는데, 그 경로 자체가 깨져 있었다. 로그인이 없는 프로젝트에서 테스트유저 전환은 단순 편의 기능이 아니라 **다인원 시나리오 QA의 유일한 진입점**이므로, 별도 기능처럼 가볍게 다루면 안 된다.

---

## 9. 의사결정

### 사용자가 준 정책 (원문)

Q4(신호 전송 주기 / 무엇을 기준으로 "현장에 있다"고 판정할 것인가)에 대한 답변:

> 아니 앱이 켜져있을땐, 3분 타이머랑 제보 및 답변할때 위치 체크하잖아. 이건 변하지않는거야. 현장 사용자 보여줄때랑 추후 질문 알람 대상 사용자를 집계할때는 앱 종료되어도, gps 인증 30분이후까지는 사용자로 친다는 로직을 구현해달라고

**이 원문이 구현에 미친 영향**: 현장 인원 판정을 **연결 상태가 아니라 DB의 `last_seen` 타임스탬프만으로** 계산하게 만들었다. 그리고 "현장 사용자 보여줄때**랑** 추후 질문 알람 대상"이라고 두 용도를 한 문장에 묶었기 때문에, 판정 로직을 `services/presence.py`의 공용 함수(`count_onsite_users`, `get_onsite_user_ids`)로 빼서 **기능 8이 그대로 재사용하도록** 설계했다. `get_onsite_user_ids`는 지금 아무도 호출하지 않지만, 이 문장 때문에 미리 만들어 둔 것이다.

세션·소켓·`is_active` 같은 접속 상태 컬럼은 테이블에 아예 없다. 그래서 앱을 껐어도 30분 안이면 집계되고, 반대로 앱을 켜두기만 하고 신호를 안 보내면 30분 뒤 빠진다.

### 사용자가 선택지 중에서 고른 것 (Q1~Q3)

전부 `AskUserQuestion`으로 대가를 함께 제시하고 사용자가 택한 것이다.

| # | 쟁점 | 선택 | 버린 쪽과 그 이유 |
|---|---|---|---|
| **Q1** | 위치 신호를 언제 보내는가 | **C — 기존 `POST /reports/verify-location`에 얹기.** 신규 엔드포인트 0개 | **A(제보 시점만 인정)를 버린 이유**: 현장 인원이 사실상 "최근 30분 제보 건수"와 같아져 두 숫자가 같은 말을 두 번 하게 된다. 기능 8의 알림 대상도 "방금 제보한 사람"으로 좁아진다. <br>**B(독립 `POST /presence/ping` 신설)를 버린 이유**: 사용자 동의 없이 주기적으로 위치를 보내는 채널이 새로 생긴다. 무엇보다 **Live 화면에 이미 3분 주기 GPS 재확인 타이머가 돌고 있어서**(`live_screen.dart:78`) 채널을 새로 팔 이유가 없었다 |
| **Q2** | 어느 관광지인지 누가 판정하나 | **A — 앱이 `content_id`를 지정.** 서버는 좌표로 관광지를 추정하지 않는다 | **B(서버가 좌표로 추정)를 버린 이유**: `function.md`는 B라고 적혀 있지만 [002](002-report-gps-verification.md) 9절이 이미 반대를 확정했다 — "GPS만으로 관광지를 추정하면 주변 여러 곳 중 아무거나 골라잡는다". 경복궁·광화문처럼 밀집한 곳에서 **엉뚱한 관광지에 인원이 쌓인다.** 이 기능의 산출물은 결국 기능 8의 푸시 대상 명단이라, 대상이 어긋나면 엉뚱한 사람에게 알림이 간다. 매 신호마다 TourAPI 호출이 붙는 부담도 있다 |
| **Q3** | `presences` 구조와 24시간 파기 방식 | **A — 1행 UPSERT + 신호 수신 시 곁다리 정리.** 스케줄러 도입 안 함 | **B(방문 이력 append + 정리 배치)를 버린 이유**: 3분 주기면 **1인당 하루 480행의 이동 경로**가 DB에 남아 `function.md`의 "경로 복원 불가" 약속을 정면으로 위반한다. 그리고 배치가 죽으면 삭제 약속도 **조용히** 깨진다. 이 프로젝트에는 스케줄러가 하나도 없다는 일관성도 고려했다. <br>**대가로 받아들인 것**: 신호가 전혀 없는 조용한 시간대에는 파기가 다음 신호까지 지연된다(삭제 누락은 아님) |
| **Q5** | 어느 화면까지 보여주나 | **B — 상세페이지 LIVE 상태창 + Live 페이지 헤더** (권장안 채택, 사용자에게 별도로 묻지 않음) | **C(HOT SPOTS 카드까지)를 버린 이유**: 카드의 절반이 `basis=CONGESTION`(집중률 예측)이라 **인원 데이터가 아예 없다.** 있는 칸/없는 칸이 섞이고, 정렬에 반영하면 [004](004-congestion-prediction.md)·[005](005-live-status-hotspots.md)가 지킨 "예측과 실측을 섞지 않는다"가 깨진다 |
| **Q6** | 답변 대기 질문 동봉을 이번에 하나 | **A — 이번에 포함** (권장안 채택) | **B(기능 8과 함께)를 버린 이유**: `function.md`가 "웹에서는 이게 **사실상 주 전달 경로**"라고 못 박았고, 웹 푸시 도달률이 낮다는 걸 이미 아는 상태다. 미루면 "현장 사용자에게 질문을 알릴 방법"이 당분간 **전혀 없다.** 게다가 `GET /questions?pending_only=true` 쿼리가 이미 정확히 이 목록을 돌려주고 있어서 추가 비용이 작았다 |

### 명세를 안 봐도 답이 정해져 있어서 질문하지 않은 것

| 쟁점 | 결정 | 근거 |
|---|---|---|
| **반경을 얼마로?** | 기존 **150m**(`GPS_VERIFICATION_RADIUS_M` 100 + `GPS_ERROR_MARGIN_M` 50) 재사용. presence 전용 상수 신설 금지 | [002](002-report-gps-verification.md) 9절 "인증 API와 저장 API는 동일한 상수를 공유 — 기준이 다르면 모순이 생긴다". 따로 두면 **"인증은 됐는데 인원엔 안 잡힘"**이 발생한다. [003](003-proximity-report-alert.md)의 50m는 알림용으로 일부러 좁힌 값이라 집계에 쓰면 구조적으로 과소 집계된다 |
| **위치 신호에 Credit을 주나?** | **안 준다.** `credit_ledger`에 행이 안 생긴다 | [010](010-credit-badge.md) 9절 정책 원문 "서비스에 정보를 제공하거나 다른 사용자에게 도움을 주는 행동에만 보상". 위치 신호는 정보 제공도 도움도 아닌 배경 동작이다. [011](011-bookmarks-and-weather-badge.md)에서 북마크에 안 준 것과 같은 판정 |
| **인원 조회 전용 엔드포인트를 만드나?** | **안 만든다.** `LiveStatusResponse`에 필드 하나 추가 | [005](005-live-status-hotspots.md) 12절이 이미 이 자리를 지정했고 코드 주석도 자리를 비워둔 상태였다. [011](011-bookmarks-and-weather-badge.md) 9절 "엔드포인트 하나가 늘면 라우터·스키마·Dart·QA가 전부 따라 는다" |
| **인원 필드를 `Optional`로 두나?** | **아니다. `int`(0 허용).** `available: false` 폴백 패턴을 안 쓴다 | 그 패턴은 [008](008-weather-open-meteo.md)에서 **외부 API**(날씨·집중률) 실패용으로 도입한 것이다. presence는 우리 DB라 조회에 실패하면 **500이 정직하다.** 0을 대신 내려보내면 "아무도 없음"과 "못 셌음"이 구분되지 않는다 |
| **응답 필드 표기** | **snake_case** | 확정 규약. `function.md` 5장의 "camelCase 통일"은 폐기 판정된 문장이다 |

---

## 10. 배운 것

**1. "만료"를 구현하는 방법은 두 가지고, 하나는 거의 항상 틀렸다.**
상태 칸 + 배치는 "배치가 늦으면 DB가 거짓말한다"는 결함을 구조적으로 안고 있다. 조회 시점 계산은 그럴 수가 없다. 이 프로젝트는 TTL·하루 리셋·Credit 상한을 전부 이 방식으로 했고, presence도 같은 방식이라 배울 것이 새로 없었다 — 오히려 **"일관되게 같은 방식을 쓴다"는 것 자체가 자산**이라는 걸 배웠다.

**2. 프라이버시 약속은 코드가 아니라 스키마로 지킨다.**
"좌표를 저장하지 않겠다"를 코드로 지키면 언젠가 누가 칸에 값을 넣는다. 칸이 없으면 넣을 수가 없다. "방문 이력을 안 쌓는다"도 마찬가지로 UNIQUE 제약 하나로 **원리적으로 불가능**하게 만들었다. 정책 문서보다 스키마가 강하다.

**3. 배경 동작의 실패는 사용자에게 보고할 일이 아니다.**
사용자가 누른 적 없는 동작이 실패했다고 다이얼로그를 띄우면, **정상 상황이 오류로 보고된다.** 다만 이건 "실패를 숨기라"는 뜻이 아니다 — 같은 API라도 사용자가 버튼을 눌러 부른 경우에는 기존대로 서버 메시지를 그대로 보여준다. **누가 시작한 동작인지에 따라 실패 표시 방식이 달라야 한다.**

**4. 0과 "모름"은 화면에서 반드시 달라 보여야 한다.**
"현장 0명"은 정상값이고 "조회 실패"는 문제다. 둘 다 "0명"으로 그리면 화면만 보고는 구분할 수 없다. 상세페이지는 실패 시 **`—` + 빨간 배너**로, Live 페이지는 **줄 자체를 감추는** 방식으로 갈랐다. 이건 [005](005-live-status-hotspots.md)에서 가장 비쌌던 버그("에러를 빈 상태로 뭉갬")의 재발 방지책이다.

**5. 아직 소비자가 하나뿐인 판정도 함수로 빼 둘 이유가 있다.**
`get_onsite_user_ids`는 지금 **아무도 호출하지 않는다.** 그런데도 만든 이유는, 기능 8을 만들 때 그 사람이 "새로 쿼리를 짜는" 선택지 자체를 없애기 위해서다. 나중에 짜면 조건이 미묘하게 갈리고, 그 어긋남은 테스트로 안 잡힌다.

---

## 11. 현재 한계

### 구조적 한계 (설계상 받아들인 것)

1. **로그인이 없어 사용자가 사실상 1명이다.** `deps.get_current_user_id()`가 항상 `test_user`를 돌려주므로 **현장 인원은 거의 항상 0 또는 1이다. 이건 버그가 아니다.** 여러 명 시연은 `TEST_MODE=true` + `X-Test-User-Id` 헤더(마이 화면 "테스트유저 전환")로만 가능하다. → 실제 로그인은 구현 순서 9단계.
2. **웹은 탭을 닫으면 즉시 끊긴다.** 인원은 구조적으로 과소 집계되며, 30분 창이 완화할 뿐 해결하지 못한다 (`function.md` 기능 6이 스스로 경고한 한계).
3. **상세페이지만 열어둔 사용자는 진입 시 1회만 잡혀 30분 뒤 자동으로 빠진다.** 실제로 계속 있어도 그렇다. Q4-A가 명시적으로 받아들인 대가이고, 전용 타이머를 만들지 않았다.
4. **조용한 시간대에는 24시간 파기가 지연된다.** 신호가 들어올 때 곁다리로 돌기 때문. 다음 신호가 오면 밀린 것까지 함께 지운다(삭제 누락은 아니다).
5. `verify-location`은 매 호출마다 TourAPI 상세 조회를 한다. presence를 여기 얹었으므로 **신호 주기만큼 TourAPI 호출이 는다.**

### QA에서 남은 것 (실패 0건, 관찰 3건)

| # | 내용 | 조치 |
|---|---|---|
| **O-1** | `livespot_app/lib/config/constants.dart:8`의 `gpsVerificationRadius = 500`이 **코드 전체에서 참조되지 않는 죽은 상수**다. 서버 값 150과 다르지만 반경 판정은 전적으로 서버가 하므로 "불일치"가 아니라 "미사용" | **수정 완료 (2026-09-10).** 상수 삭제. 삭제 전 전체 참조 검색으로 미사용 재확인 |
| **O-2** | `spot_detail_screen.dart:112` — 답변 후 재신호가 실패하면 `_pendingQuestions` 배너에 답변 완료된 질문이 남는다. **데이터 오염은 없고 화면 갱신 지연뿐** (답변 제출은 서버가 매번 GPS를 재검증한다) | **수정 완료 (2026-09-10).** `if (!result.presenceRegistered) { setState(() => _pendingQuestions = []); return; }`로 교체해 `live_screen.dart:133`과 처리 방식 통일. `flutter analyze` 71건(기존과 동일, 신규 issue 0건) 재확인 |
| **O-3** | `03_flutter_wiring.md`가 "flutter analyze 전체 72건"이라 적었으나 실측은 **71건** | 핵심 주장(error 2건이 기존 문제, 이번 변경분 issue 0건)에는 영향 없는 단순 오기 |

### 검증하지 못한 것 (통과로 기록하지 않음)

| 항목 | 이유 |
|---|---|
| **`DEMO_BYPASS_GPS=true` 런타임 동작** | 코드 경로(`reports.py:196` → `:211`)는 읽어서 확인했으나, 실측하려면 `.env` 수정 + 서버 재기동이 필요해 이번 QA에서 보류. 백엔드 담당이 측정한 결과는 `02_backend_contract.md`에 있으나 QA가 직접 본 것이 아니라 **통과로 기록하지 않았다** |
| **실제 브라우저 화면 렌더링** | 위젯 코드의 분기 로직은 읽어서 검증했으나 픽셀 결과는 미확인. **사용자가 직접 볼 몫** |
| **presence 동시 갱신 시 `IntegrityError` 폴백 경로** (`presence.py:85-99`) | 같은 사용자의 신호 2건이 정확히 동시에 도착해야 재현되는 경쟁 조건이라 로컬에서 결정적으로 유발하지 못했다. 구조는 읽어서 확인 |
| **Railway Postgres에서의 마이그레이션 실적용** | 로컬 SQLite에서만 확인. 신규 테이블 생성만이라 양쪽에서 도는 형태이나 실적용은 미확인. `Dockerfile:15`의 `alembic upgrade head`로 배포 시 자동 적용된다 |

### 통과한 것 (기록용)

QA 최종 판정은 **실패 0건**이다. 특히 이 프로젝트에서 반복돼 온 경계면 버그 세 유형이 전부 사전에 막혔다 — 신규 3필드의 키가 실측 응답 기준 문자 단위 일치(`null명 | null건` 방지), 조회 실패가 `0`으로 둔갑하지 않도록 양쪽 화면에서 분리, 시간창이 다른 두 숫자에 각각 기준 문구를 붙이고 헤더 대표 문구 제거.

---

## 12. 다음 단계

1. **기능 8 (질문 푸시 알림) — 이번 기능의 원래 목적지.**
   **`services/presence.py::get_onsite_user_ids(db, content_id)`를 그대로 호출하면 대상 명단이 나온다.** 이번에 미리 그 형태로 만들어 뒀으니 **판정 쿼리를 새로 짜지 말 것** — 새로 짜면 화면 숫자와 알림 대상이 어긋난다. 이번에 만들지 않은 것은 `device_tokens` / `push_jobs` / `push_log`와 FCM 발송뿐이다.
2. ~~**O-2 두 화면 처리 통일**~~ — 완료 (2026-09-10). 11절 참조.
3. ~~**O-1 죽은 상수 삭제**~~ — 완료 (2026-09-10). 11절 참조.
4. **`DEMO_BYPASS_GPS=true` 실측** — `.env` 수정 + 서버 재기동이 필요한 작업이라 다른 검증과 함께 몰아서 한 번에 한다. 이걸 켜야 개발 PC에서도 현장 인원이 실제로 1 이상으로 오르는 화면을 볼 수 있다.
5. **배너에서 답변한 뒤 `QaSection` 목록 자동 갱신** — 배너 자신과 현장 인원은 `onAnswered`에서 다시 읽지만, `QaSection`은 자기 `Future`를 스스로 들고 있어 화면을 다시 열어야 반영된다. 기존 구조 문제이고, `bug-patterns.md` 1-3(탭을 살려두는 구조)과 같은 계열이다.
6. **로그인 (구현 순서 9단계)** — 이게 붙기 전까지 현장 인원 숫자는 시연용으로만 의미가 있다.
