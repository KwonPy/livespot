# LiveSpot 설계서

> **이 문서의 역할** — 기능 전체 지도와 아직 만들지 않은 것의 설계. **이미 만든 것의 상세한 기록은 [`docs/worklogs/`](docs/worklogs/)에 있다.**
>
> **정책이 충돌하면 작업일지 9절(의사결정)이 이긴다.** 이 문서는 시점이 더 오래됐다.
>
> **현행화 기준: 2026-09-18** (작업일지 [001](docs/worklogs/001-tourapi-spots.md)~[021](docs/worklogs/021-briefing-cluster-and-qa-ux.md) 및 실제 코드 대조 완료).

---

## 1. 한눈에 보는 현황

| # | 기능 | 상태 | 기록 |
|---|---|---|---|
| 1 | 회원가입 · 로그인 (카카오) | ✅ 구현 — 카카오 로그인 + 서비스 전용 JWT, 앱 전용 unique 닉네임(카카오 닉네임·프로필사진 미사용) | [016](docs/worklogs/016-kakao-login.md) · [017](docs/worklogs/017-app-owned-unique-nickname.md) |
| 2 | 현장 제보 저장 | ✅ 구현 (Credit 포함) | [002](docs/worklogs/002-report-gps-verification.md) · [010](docs/worklogs/010-credit-badge.md) |
| 3 | GPS 현장 인증 | ✅ 구현 — 판정 반경은 **250m**(200m + 오차 50m). 2026-09-17에 150m에서 확대 | [002](docs/worklogs/002-report-gps-verification.md) · [003](docs/worklogs/003-proximity-report-alert.md) |
| 4 | Credit 보상 | ✅ 구현 (제보 +10 / 답변 +5 / 질문 0) | [010](docs/worklogs/010-credit-badge.md) |
| 5 | LIVE 상태창 · 핫스팟 | ✅ 구현 (MVP 범위, 카드 썸네일 포함) | [005](docs/worklogs/005-live-status-hotspots.md) · [011](docs/worklogs/011-bookmarks-and-weather-badge.md) |
| 6 | 현장 사용자 수 집계 | ✅ 구현 (신규 엔드포인트 0개 — `verify-location`/`live/status`에 얹음) | [013](docs/worklogs/013-onsite-user-count.md) |
| 7 | 실시간 Q&A | ✅ 구현 (Credit 포함) | [006](docs/worklogs/006-realtime-qna.md) · [007](docs/worklogs/007-live-page-restructure.md) · [010](docs/worklogs/010-credit-badge.md) |
| 8 | 푸시 알림 (질문/답변 알림) | 🟡 **인앱 알림으로 구현 완료** — 서버가 알림 행을 남기고, **앱이 WebSocket(`GET /api/notifications/ws`) 신호를 받아 즉시 재조회**한다(끊기면 7초 폴링으로 자동 폴백). 표시는 **모달 다이얼로그**(버튼으로만 닫힘). 재접속 시에는 "새 알림 N건" 요약 다이얼로그. 알림 종류는 `NEW_QUESTION`·`NEW_ANSWER` 2종. 만료는 연결된 질문의 2시간. **2026-09-13 정책 축소(015)**: 전역 ON/OFF 토글·`user_notification_settings` 테이블·Live 답변대기 배너·MyPage 알림 탭 **전부 제거**. **2026-09-18**: "확인하기"를 누르면 질문 상세(읽기 전용 시트)를 거치지 않고 **곧장 관광지 상세페이지로 이동** — 답변은 여전히 그 안에서 GPS 재인증을 거쳐야만 가능. **실제 Web Push/FCM(탭을 닫아도 오는 것)은 범위 밖**(014 Q2-C, P21로 최종 출품물이 모바일 웹서비스 확정) | [003](docs/worklogs/003-proximity-report-alert.md) · [014](docs/worklogs/014-question-answer-notification.md) · [015](docs/worklogs/015-notification-policy-reduction.md) · [021](docs/worklogs/021-briefing-cluster-and-qa-ux.md) |
| 9 | 혼잡도 판정 (예측/실측 분리) | ✅ 구현 — 집중률 캐시 싱글턴화·실패/빈응답 구분(018) | [004](docs/worklogs/004-congestion-prediction.md) · [018](docs/worklogs/018-congestion-quota-fix.md) |
| 10 | AI 브리핑 | ✅ 구현 — Gemini 실연동. `GET /spots/{id}/briefing`이 날씨·집중률 예측·당일 제보를 재료로 3~4문장 생성. 응답 `source` 필드(`AI`/`CACHED_AI`/`TEMPLATE`/`NONE`)로 진짜 AI인지 표시, 3단 폴백으로 **404 말고는 항상 200**. **2026-09-18**: 현장 제보 반영을 "최근 1건"에서 **시간창 기반 종합**으로 확대 — 직전 제보와 간격이 1시간 이내로 이어진 묶음이면 혼잡도/대기/주차를 최빈값으로 종합 | [009](docs/worklogs/009-ai-briefing.md) · [021](docs/worklogs/021-briefing-cluster-and-qa-ux.md) |
| 11 | 뱃지 | ✅ 구현 | [010](docs/worklogs/010-credit-badge.md) |
| 12 | MyPage | ✅ 구현 — 프로필 카드(닉네임·뱃지·누적 Credit) + 메뉴 6개(내 제보 · 내 Q&A · Credit 내역 · 북마크 · 앱 정보 · 로그아웃). **죽은 메뉴는 없다** — "GPS 인증 설정"·"알림"·"위치 권한"·"고객센터"는 전부 제거됐고 로그아웃은 실동작한다 | [011](docs/worklogs/011-bookmarks-and-weather-badge.md) · [014](docs/worklogs/014-question-answer-notification.md) · [015](docs/worklogs/015-notification-policy-reduction.md) |
| — | 관광지 조회 · 지도 | ✅ 구현 (대표이미지 CORS 프록시 포함). ⚠️ "내 주위 관광지"는 TourAPI 위치 색인 누락분을 놓친다 — 데이터셋 한계로 감수, 보완 조회는 미구현 | [001](docs/worklogs/001-tourapi-spots.md) · [011](docs/worklogs/011-bookmarks-and-weather-badge.md) · [019](docs/worklogs/019-nearby-spots-data-gap.md) |
| — | 날씨 | ✅ 구현 — Open-Meteo 실시간 호출, 상세페이지 날씨 배지 | [008](docs/worklogs/008-weather-open-meteo.md) · [011](docs/worklogs/011-bookmarks-and-weather-badge.md) |
| — | 북마크 | ✅ 구현 | [011](docs/worklogs/011-bookmarks-and-weather-badge.md) |
| — | 배포 | ✅ 구현 — Railway에 DB·백엔드·웹앱 3개 서비스 | [012](docs/worklogs/012-railway-deploy.md) |

**핵심 구간(제보 → LIVE → Q&A)에 이어 Credit·뱃지·현장 인원 집계·AI 브리핑까지 끝났고, MyPage도 죽은 메뉴 없이 전부 실데이터로 채워졌다.** **질문/답변 알림(기능 8)도 인앱 범위에서 끝났다** — 현장 인원 집계(기능 6)의 `get_onsite_user_ids()`를 그대로 재사용해 대상을 판정하므로, 화면의 "현장 N명"과 알림 대상이 어긋나지 않는다. **로그인(기능 1)도 카카오 + 앱 전용 unique 닉네임으로 끝났다** — 더 이상 고정 `test_user`가 아니라 실제 다중 사용자다.

**남은 것은 실제 Web Push · 운영 정비(신고·제한·보관정책) · "내 주위 관광지" 보완 조회([019](docs/worklogs/019-nearby-spots-data-gap.md)) 셋뿐이다.**

> ⚠️ **아래 "기능 8. 푸시 알림" 절(FCM 통일 · `device_tokens`/`push_jobs`/`push_log` 테이블 · 대기열+워커 · 발송 상한 3종 · 알림 30분 만료)은 설계 시점 문서이고 전부 폐기됐다.** 실제로 채택된 정책은 [014](docs/worklogs/014-question-answer-notification.md) 9절 + [015](docs/worklogs/015-notification-policy-reduction.md) 9절이다 — 인앱 WebSocket+폴링(큐·워커 없음), 테이블은 `notifications`/`push_subscriptions`(`user_notification_settings`는 015에서 **드롭**), 발송 상한 없음, 만료는 연결된 질문의 2시간. **충돌하면 일지가 이긴다.**

---

## 2. 전체 구조

```
[Flutter 웹앱]  위치 신호 · 제보/질문/답변
        │
        ▼
[FastAPI]  ├ 저장·검증 (제보/질문/답변, GPS 거리 재계산)
           ├ 집계     (LIVE 상태, 핫스팟 랭킹)
           │
           ├──▶ [SQLite / PostgreSQL]  ← 우리 데이터만
           └──▶ [TourAPI · 집중률 API · Gemini · 날씨]  ← 외부, 읽기 전용, DB 미저장
```

### 설계 원칙 4가지

1. **계산은 전부 서버에서.** 앱은 받은 숫자를 그리기만 한다.
2. **공공데이터는 실시간 호출.** 로컬 DB에 복사하지 않는다 (분 단위 메모리 캐시는 허용). 관광지는 `spots` 테이블 없이 TourAPI `content_id` 문자열로 참조한다.
3. **읽기는 실패해도 화면이 살아있게, 쓰기는 엄격하게.** 날씨·AI가 실패해도 대체 내용을 보여주고, 제보 저장은 GPS·중복검사를 모두 통과해야 저장한다.
4. **정직하게 만든다.** 없는 데이터를 숫자로 지어내지 않는다. "현장 18명"이 "최근 30분 내 신호 18명"이면 화면에도 그렇게 쓴다.

---

## 3. 구현된 기능 — 지켜지고 있는 규칙

배경·문제·의사결정의 상세는 각 작업일지에.

| 기능 | 규칙 |
|---|---|
| **제보** | 판정 반경 = `200m + 오차 50m` = **250m** (`GPS_VERIFICATION_RADIUS_M`+`GPS_ERROR_MARGIN_M`). 2026-09-17에 150m가 타이트하다는 사용자 판단으로 확대. 서버가 매 요청 좌표 재계산 (앱의 "인증 완료" 상태를 믿지 않음). `client_request_id`로 중복 제출 방지 |
| **GPS 인증** | 인증 API와 저장 API가 **같은 상수**를 공유 — "인증은 됐는데 제출은 거부" 모순 방지. 인증 요청에 `content_id` 필수 (GPS로 관광지를 추정하지 않음) |
| **적용 범위** | 제보 = 거부 · Q&A 답변 = 거부 · 리뷰 = 허용(표시만) · **질문 = 제한 없음** (질문자는 원래 멀리 있는 사람) |
| **LIVE** | 시간창 2개 — 활동성은 **최근 2시간**, 현재 혼잡도/대기/주차는 **당일(KST)**. 당일 제보가 없으면 `null` (어제 값을 보여주지 않는다) |
| **핫스팟** | 1순위 실제 제보(혼잡도↓ → 최신성↓ → 건수↓) — **지역·타입 제한 없이 전국**. 남는 자리만 2순위 집중률 예측 — **서울 25개 시군구 + 콘텐트타입 "관광지"(12)로 한정**([018](docs/worklogs/018-congestion-quota-fix.md): 상대 비율 왜곡 방지 + API 쿼터 절약). **값을 섞지 않고 순서만 이어 붙인다.** `basis` 필드로 출처 구분 |
| **혼잡도** | 예측(집중률)과 실측(제보)을 **절대 하나로 합치지 않는다.** 지도 마커 = 예측 전용. 용어도 분리 — 예측은 "여유/보통/**높음**", 제보는 "여유/보통/**혼잡**". `CongestionService`는 **모듈 전역 싱글턴 1개**(인스턴스가 늘면 캐시가 갈라져 쿼터가 배로 샌다). API **실패**와 "정상 응답인데 0건"을 구분 — 실패는 120초만 캐싱, 성공은 당일 자정까지 |
| **Q&A** | 질문 TTL 2시간, 하루 단위 리셋 — 둘 다 **상태 컬럼·배치 없이 조회 시점에 계산**. 본인 질문 답변 불가. 답변은 GPS 인증 필수 |
| **Live 페이지** | GPS OFF: HOT SPOTS → 전체 Q&A / GPS ON+인증: 내 현장 Q&A → HOT SPOTS → 전체 Q&A. "전체 LIVE Q&A"는 **조회 전용**. 탭이 `IndexedStack`으로 살아 있으므로 Q&A 섹션은 `isActive`로 **다시 보일 때 재조회**한다([020](docs/worklogs/020-real-test-result-and-revise.md) 1번) |
| **인앱 알림** | 종류 2개(`NEW_QUESTION`·`NEW_ANSWER`)뿐. **전역 ON/OFF 토글 없음**([015](docs/worklogs/015-notification-policy-reduction.md)에서 테이블까지 드롭). 전달은 WebSocket 신호 → 재조회, 끊기면 7초 폴링. 모달은 `PopScope(canPop: false)`로 **버튼으로만** 닫힌다(뒤로가기·Esc로 닫히던 버그 수정). 알림 발췌는 **원 질문 본문**에서 뽑는다 — 답변 본문을 노출하지 않는다. "확인하기"는 **곧장 관광지 상세페이지로 이동**한다(2026-09-18, [021](docs/worklogs/021-briefing-cluster-and-qa-ux.md)) — 답변 가능 여부는 상세페이지의 GPS 재인증이 그대로 판정 |
| **자동 알림(제보 유도)** | foreground 전용 (백그라운드·OS Geofencing 아님). 반경 **150m**(2026-09-17에 50m에서 확대), 같은 곳 2시간 쿨다운, 15초마다 위치 재확인, 겹치면 가장 가까운 1곳만 |
| **AI 브리핑** | 재료 4갈래(관광지 개요·날씨·집중률 **예측**·당일 **제보**)를 프롬프트에 **각각 별개 라벨**로 넣는다(예측/실측 분리 원칙). 응답 `source`가 `AI`·`CACHED_AI`일 때만 앱이 "Gemini로 생성됨" 라벨을 붙인다. 404 외에는 **항상 200** — 키 부재·타임아웃·쿼터 소진도 `TEMPLATE`로 내려간다. 예외 메시지는 응답에 싣지 않는다. 현장 제보는 **1건이 아니라 시간창 묶음**이 재료다 — 직전 제보와 간격이 1시간 이내면 계속 묶어 혼잡도/대기/주차를 최빈값으로 종합, 1시간 넘으면 최신 1건만(2026-09-18, [021](docs/worklogs/021-briefing-cluster-and-qa-ux.md)) |
| **작성자 표시** | 질문·답변·제보 카드는 공용 `AuthorHeader` 위젯 하나로 통일 — 아바타 → 닉네임 → 현장인증 뱃지 → 시간 순. 아바타는 전 사용자 공통 `assets/images/default_profile.png`. **질문자에게는 인증 뱃지를 붙이지 않는다**(질문은 위치 제한이 없어 인증 개념 자체가 없다) |
| **외부 표기** | 앱 화면에 "한국관광공사"를 노출하지 않는다([020](docs/worklogs/020-real-test-result-and-revise.md) 5번). 코드 주석·README·작업일지는 대상 아님 |
| **Credit** | 제보 +10 · 답변 +5 · 질문 0. `credit_ledger` 통장식 원장에 적립·차감을 쌓고, `users.credit_balance`는 캐시일 뿐 원장 합계가 진실. 뱃지 등급은 **누적 총액** 기준(잔액 아님) |
| **뱃지** | 크레딧을 리워드·현금성 포인트로 교환하지 않는다. 게이미피케이션만(새싹→Spot 탐방객→Spot 탐험가→베테랑→마스터) |
| **북마크** | `user_id`+`spot_content_id` UNIQUE. 추가·해제(`POST`/`DELETE`)는 **멱등**(중복 호출도 200, 409/404 없음). Credit 미지급·GPS 미요구·만료 없음. 목록 항목 탭 시 **관광지 상세페이지로 이동**(내 제보·내 Q&A와 달리) |
| **현장 인원** | 신규 엔드포인트 없이 기존 `POST /reports/verify-location`이 성공하면 부수효과로 `presences` 1행 UPSERT. `content_id`는 앱이 지정(서버가 좌표로 추정 안 함), 좌표는 저장 안 함(거리만 남김). 인원수는 상태 컬럼 없이 **조회 시점에 `last_seen ≥ 지금-30분`으로 계산**(만료 배치 없음). Credit 미지급 |
| **대표이미지** | TourAPI 이미지 CDN이 CORS 헤더를 안 보내 Flutter Web에서 직접 로드 시 항상 실패한다. 백엔드 `GET /api/images/proxy?url=`이 대신 fetch해 CORS 헤더를 붙여 중계— 앱은 원본 URL을 절대 직접 그리지 않고 이 프록시를 거친다. 화이트리스트로 TourAPI 이미지 호스트만 허용(SSRF 방지) |
| **로그인 · 닉네임** | 로그인 수단은 카카오 하나. 서버가 카카오 토큰을 직접 검증하고 **서비스 전용 JWT**를 발급한다(Firebase 미사용). 카카오에서 받는 것은 **회원번호뿐** — 닉네임·프로필 사진 동의항목을 받지 않는다. `users.nickname`은 **앱에서 직접 입력한 unique 값**이고, 미설정 상태는 `nickname IS NULL` 하나로만 표현한다. 식별 키는 여전히 `users.id`(UUID)뿐 — 어떤 쿼리도 닉네임으로 사용자를 찾지 않는다. 닉네임 미설정 사용자의 **모든 쓰기는 서버가 403 + `{"code": "NICKNAME_REQUIRED"}`로 거부**한다(판정은 `deps.py::get_current_user_id()` 한 곳). `users.profile_image_url`은 컬럼만 남고 **항상 NULL** |
| **개발 스위치** | `DEMO_BYPASS_GPS`(거리 판정 우회) · `TEST_MODE`(헤더로 작성자 변경). **배포 시 둘 다 반드시 False** (현재 코드 기본값도 둘 다 `False`) |

---

## 4. 기능별 상세 설계 (설계 시점 원안 + 현재 상태)

> ⚠️ **이 장은 대부분 설계 시점 원안이다.** 아래 6개 중 기능 1·4·10·11·12는 **이미 구현 완료**됐고, 기능 8만 인앱 범위까지 구현됐다. 각 절 머리의 상태 표시를 먼저 읽을 것 — 원안과 실제 구현이 다른 곳은 **작업일지가 이긴다.**

### 기능 1. 로그인 (카카오) — ✅ 구현 완료

> **현재 상태**: 원안과 다른 부분이 있다 — Firebase 브리지 없이 서버가 직접 카카오 토큰을 검증하고 자체 JWT를 발급하며(Firebase Auth 미사용), 카카오 닉네임·프로필 사진은 **동의항목 자체를 받지 않고**(회원번호만) 앱 전용 unique 닉네임을 별도로 받는다. 프로필 사진은 전 사용자 공통 기본 이미지다(P34 → P50 켜짐 → **P51 재폐지**, 2026-09-17 확정). **실제 정책·구현은 [016](docs/worklogs/016-kakao-login.md)·[017](docs/worklogs/017-app-owned-unique-nickname.md) 일지가 이긴다.** 비로그인/로그인 필요 구간 구분표는 아래 그대로 유효하다.

**확정안**: 로그인 수단은 **카카오 하나만** 제공한다 (구글·이메일 등 추가 없음). 원칙은:

> **정보를 보는 것은 자유롭게, 정보를 생산하고 참여하는 것은 로그인.**

여러 로그인 방식을 지원하면 인증·예외 처리로 개발 범위가 불필요하게 커지고, 반대로 모든 기능에 로그인을 강제하면 "들어오자마자 관광지 정보부터 보고 싶은" 사용자의 진입장벽이 높아진다는 절충.

| 비로그인 허용 | 로그인 필요 |
|---|---|
| 관광지 검색·지도·상세정보, 날씨, 혼잡도/현장 인원, AI 브리핑, 질문 조회 | 현장 제보, 질문 작성, 질문 답변, 실시간 채팅 참여, MyPage, Push 알림 설정 |

로그인한 사용자는 서비스 내부 `user_id`를 발급받아 관리한다 (카카오 ID를 그대로 노출하지 않음). 비로그인 '둘러보기'는 유지(읽기만). 쓰기는 로그인 필수.

### 기능 4. Credit 보상 — ✅ 구현 완료

> **현재 상태**: 아래 확정안대로 구현됐다([010](docs/worklogs/010-credit-badge.md)). 조회 API도 붙어 있다 — `GET /api/credits/me`(잔액·뱃지) · `/me/ledger`(내역) · `/me/activity`(제보·답변 건수).

**확정안** — 적립 대상과 금액:

| 사용자 행동 | 크레딧 |
|---|---:|
| 📍 현장 제보 | **+10** |
| 💬 질문 답변 | **+5** |
| ❓ 질문 작성 | **0** |

핵심 원칙: **"서비스에 정보를 제공하거나 다른 사용자에게 도움을 주는 행동에 보상한다."** 질문 작성은 정보를 요청하는 행동이라 보상 대상이 아니다 — 크레딧을 주면 보상을 노린 의미 없는 질문이 반복될 수 있다. 답변은 실제로 다음 방문자를 돕는 행동이므로 보상 명분이 있다.

- `credit_ledger` 테이블 — **잔액 숫자 하나가 아니라 통장 거래내역처럼 적립·차감을 쌓는다.** "왜 줄었죠?"에 답할 수 있고, 회수도 삭제가 아니라 마이너스 한 줄로 남는다.
- `users.credit_balance`는 빠른 조회용 캐시. 원장 합계가 진실.
- 이중 지급 방지 2중 장치: `client_request_id`(기능 2) + "이 건에 대한 적립은 1회만" DB 제약.
- 뱃지 등급은 잔액이 아니라 **누적 총액** 기준 (써서 줄었다고 등급이 내려가면 안 된다). 등급표는 기능 11(뱃지) 참고.
- **복잡한 평판·사용자 평가 시스템은 만들지 않는다.** 대신 최소한의 제한만 둔다 — 같은 장소 하루 3건까지만 적립 (초과해도 제보 자체는 저장). 행동별 일일 지급 상한의 세부 숫자는 구현 단계에서 확정.
- 크레딧은 리워드나 현금성 포인트로 **교환하지 않는다** (기능 11 참고).

**연결 지점 (중요)** — 제보 +10 → `api/reports.py`의 `create_report`, 답변 +5 → `api/questions.py`의 `create_answer`. 각각 **하나의 트랜잭션**으로 묶어야 "제보는 됐는데 포인트는 안 들어옴"이 안 생긴다.

### 기능 8. 푸시 알림 — 🟡 인앱 범위만 구현, 아래 원안은 대부분 폐기

> **현재 상태 (실제로 돌아가는 것)**
>
> | 항목 | 실제 구현 |
> |---|---|
> | 전달 경로 | 인앱. `GET /api/notifications/ws`(WebSocket) 신호 → 앱이 `GET /api/notifications` 재조회. 끊기면 **7초 폴링**으로 자동 폴백 |
> | 알림 종류 | `NEW_QUESTION` · `NEW_ANSWER` 2종 |
> | 대상 판정 | `services/presence.py::get_onsite_user_ids()` 재사용 (아래 원안 그대로 유효) |
> | 표시 | 모달 다이얼로그(`PopScope(canPop: false)` — 버튼으로만 닫힘) + 미읽음 배지. 재접속 시 "새 알림 N건" 요약. "확인하기"는 질문 상세(읽기 전용 시트)를 거치지 않고 **곧장 관광지 상세페이지로 이동**(2026-09-18) — 답변은 그 안의 GPS 재인증을 거쳐야 가능 |
> | 발송 상한 | **없음** (원안의 3종 상한 전부 폐기) |
> | 만료 | 연결된 질문의 TTL 2시간 (알림 자신의 30분 만료는 폐기) |
> | 테이블 | `notifications` · `push_subscriptions`(스키마만, 미사용). `user_notification_settings`는 [015](docs/worklogs/015-notification-policy-reduction.md)에서 **드롭** |
> | 큐·워커 | **없음** (요청 트랜잭션 안에서 알림 행 생성) |
> | 전역 ON/OFF 토글 | **없음** — 015에서 제거 |
>
> **남은 것은 실제 Web Push/FCM뿐**(탭을 닫아도 오는 알림). `push_subscriptions` 테이블이 그 자리를 비워 두고 있다.

**확정안 (⚠️ 아래는 설계 시점 원안 — 위 표와 다르면 위가 맞다)** — 질문이 등록되면 **해당 관광지의 최근 30분 현장 사용자**에게 알림한다. **알림 대상 판정은 Flutter가 아니라 FastAPI가 한다.** 기능 6이 이미 이 판정을 `services/presence.py::get_onsite_user_ids(db, content_id)`로 빼 뒀으므로 ([013](docs/worklogs/013-onsite-user-count.md) 참고), 여기서 새로 쿼리를 짜지 않고 그 함수를 그대로 호출해 대상 명단을 받는다 — 화면에 뜨는 인원수와 알림 대상이 어긋나지 않도록.

알림 수단은 **FCM 하나**로 통일하되 앱 상태에 따라 표현만 다르게 한다: 포그라운드 = 앱 내부 알림/배너, 백그라운드 = 시스템 Push, 종료 상태 = 시스템 Push(기본 방향). 앱 내부 팝업만 쓰면 앱을 안 보고 있는 현장 사용자에게 못 알리고, 반대로 무조건 시스템 Push만 쓰면 앱을 보고 있을 때도 매번 외부 알림 형태가 되는 문제를 절충.

| 정책 | 구현 |
|---|---|
| 알림 대상 = 해당 관광지 최근 30분 현장 사용자 | FastAPI가 `last_seen` 기준으로 판정 (Flutter는 판정하지 않음) |
| 질문마다 무분별 발송 금지 | 질문 1건당 최대 10명 |
| 1인당 시간당 최대 2회 | 발송 이력 조회로 제한 |
| 같은 장소·같은 종류 중복 금지 | 최근 6시간 내 동일 조합 제외 |

- 테이블: `device_tokens`, `push_jobs`, `push_log`, `motivation_texts`
- **대기열에 넣고 즉시 응답**한 뒤 별도 작업이 하나씩 처리한다. 서버가 여러 대여도 제한이 정확해진다.
- 보내기 전에 "발송 예약"을 먼저 기록한다 (다른 작업이 같은 사람을 또 뽑지 않게).
- 알림은 30분 뒤 자동 만료. 지난 "지금 대기 있나요?"는 도움이 안 된다.
- ⚠️ 웹 푸시는 도달률이 낮다 (아이폰 사파리는 홈 화면에 추가한 경우에만 동작). 후순위.

### 기능 10. AI 브리핑 — ✅ 구현 완료

> **현재 상태**: [009](docs/worklogs/009-ai-briefing.md)에서 실연동 완료, [021](docs/worklogs/021-briefing-cluster-and-qa-ux.md)에서 제보 반영 방식을 시간창 종합으로 확대. 아래는 원안이 아니라 **실제 구현**이다.

- `GET /api/spots/{content_id}/briefing`이 Gemini(`gemini-3.5-flash-lite`)로 3~4문장을 생성한다. 경로는 레거시 시절 그대로 재사용했고 핸들러만 전면 교체됐다.
- 재료는 **네 갈래**: 관광지 개요(TourAPI) · 현재 날씨(Open-Meteo) · 방문 집중률 **예측**(공공데이터) · 당일(KST) 현장 **제보**(우리 DB). 예측과 실측은 성격이 달라 프롬프트에도 **각각 별개 라벨**로 들어간다(기능 9 원칙). 폐기된 `CrowdednessService`(둘을 섞던 레거시)는 쓰지 않는다.
- **현장 제보 재료는 "최근 1건"이 아니라 "시간창 묶음"이다** (2026-09-18). `services/report_window.py::latest_cluster()`가 최신 제보부터 거슬러 올라가며 직전 제보와의 간격이 `BRIEFING_REPORT_CLUSTER_GAP_HOURS`(기본 1시간)를 넘지 않는 동안 계속 묶는다. 묶음이 2건 이상이면 혼잡도/대기/주차를 각각 최빈값(동률이면 최신값 우선)으로 종합해 "최근 1시간 이내 연속 제보 N건을 종합한 현재 상황"으로 프롬프트에 명시한다. 1건이면 기존과 동일하게 "가장 최근 제보"로 표기. 조회 자체 상한은 `BRIEFING_REPORT_CLUSTER_MAX`(기본 10건, 방어용).
- **캐시는 `briefing_cache` 테이블이 아니라 메모리**다. 원안의 테이블은 만들지 않았다 — 캐시 키에 **재료 서명**이 들어가므로 혼잡도·제보수·날씨가 달라지면 TTL과 무관하게 새로 생성되고, 재료가 그대로여도 6시간(`BRIEFING_CACHE_TTL_SECONDS`)이 지나면 갱신된다. 서버 재시작 시 사라지는 것은 알려진 대가다.
- **폴백 3단**: 유효 캐시(`CACHED_AI`) → AI 호출(`AI`, 5초 타임아웃) → 템플릿 문장(`TEMPLATE`). *원안의 "오래된 캐시" 단계는 없다* — 메모리 캐시라 만료되면 그냥 사라진다. **404(관광지 없음) 외에는 항상 200**이고, 예외 메시지는 응답에 싣지 않는다.
- 응답 `source` 필드(`AI`/`CACHED_AI`/`TEMPLATE`/`NONE`)가 "진짜 AI인지"를 알려주고, **앱은 AI일 때만 "Gemini로 생성됨" 라벨을 붙인다.** 원안이 경고했던 "템플릿에 AI 라벨이 붙어 있는 상태"는 해소됐다.
- 모델을 `lite`로 고른 이유는 품질이 아니라 **응답 시간**이다(실측: flash 중앙값 26초 → 사실상 매번 템플릿 폴백 / flash-lite 중앙값 1.1초). 모델이 폐기되면 `.env`의 `GEMINI_MODEL`로 덮어쓴다.

### 기능 11. 뱃지 — ✅ 구현 완료

> **현재 상태**: 아래 확정안·등급표 그대로 구현됐다([010](docs/worklogs/010-credit-badge.md)).

**확정안** — 크레딧을 직접 리워드나 현금성 포인트로 교환하지 않는다. 사용자 활동 → Credit → 누적 Credit → Badge로 이어지는 **게이미피케이션만** 가져간다. 포인트 가치·교환 기준·부정 이용·운영 정책·제휴처·소멸 정책까지 딸려오는 리워드 시스템은 공모전 MVP 범위 밖으로 명확히 제외한다.

| 누적 크레딧 | 뱃지 |
|---:|---|
| 0~49 | 🌱 새싹 |
| 50~99 | 📍 Spot 탐방객 |
| 100~199 | 🧭 Spot 탐험가 |
| 200~499 | 🏆 베테랑 |
| 500+ | 👑 마스터 |

등급 기준은 (기능 4에서 이미 확정한 대로) **누적 총액**이지 잔액이 아니다. 별도 테이블은 필요 없다 — `credit_ledger` 합계에서 계산.

### 기능 12. MyPage — ✅ 구현 완료

**확정안** — 프로필 + 보상 + 활동내역 + 계정, 4개 영역으로 단순화한다. 커뮤니티/통계 화면으로 확장하지 않는다 — 사용자가 궁금한 건 "얼마나 활동했는지", "뭘 작성했는지" 정도.

**현재 화면 구성 (실제):**

| 영역 | 내용 | 상태 |
|---|---|---|
| 👤 프로필 | 닉네임, 기본 프로필 이미지(전 사용자 공통) | ✅ |
| 🏅 보상 | 현재 뱃지, 누적 크레딧 | ✅ |
| 📝 내 제보 | 내가 작성한 현장 제보 목록 | ✅ |
| 💬 내 Q&A | 2탭 — "내가 쓴 질문" / "내가 단 답변" | ✅ |
| 💰 Credit 내역 | 통장식 적립·차감 이력 | ✅ |
| 🔖 북마크 | 저장한 관광지 (탭하면 상세페이지로) | ✅ |
| ℹ️ 앱 정보 | 서비스 소개·데이터 출처·약관류·버전 (2026-09-17 신설, "고객센터" 대체) | ✅ |
| 🚪 로그아웃 | 클라이언트 토큰 삭제 (**서버 호출 없음**) | ✅ |

**원안에서 빠진 것과 그 이유:**

- 🔔 **알림 설정(Push ON/OFF)** — [015](docs/worklogs/015-notification-policy-reduction.md)에서 토글을 테이블까지 드롭하며 제거. 알림 탭도 같이 사라져 "내 Q&A"는 2탭이다.
- 📍 **위치 권한** — 브라우저가 직접 관리하는 상태라 앱이 보여줄 게 없어 메뉴째 제거. (구 "GPS 인증 설정" 메뉴도 동일 이유로 제거됨.)

로그인(기능 1)이 전제 조건 — `user_id`가 있어야 활동내역·보상을 조회할 수 있다. 비로그인 상태에서는 로그아웃 메뉴를 아예 그리지 않는다.

---

## 5. 데이터베이스

`spots` 테이블은 **없다** (설계 원칙 2). 모든 테이블이 TourAPI `content_id`를 문자열로 직접 참조한다.

**실제로 존재하는 테이블 (마이그레이션 기준)**

| 테이블 | 역할 | 기능 |
|---|---|---|
| `users` ✅ | 계정(카카오 회원번호 + 서비스 UUID), Credit 잔액 캐시. `nickname`은 **nullable + unique**(`uq_users_nickname`), `profile_image_url`은 컬럼만 남고 항상 NULL. `TEST_MODE`일 때만 `test_user`/`seed_user_*` 시드가 함께 존재 | 1 |
| `reports` ✅ | 현장 제보 (`photo_url`은 컬럼만 존재, 항상 null) | 2·3·9 |
| `spot_notification_settings` ✅ | 관광지별 제보 유도 알림 on/off (`user_id`+`content_id` 유니크) | 3 |
| `questions` ✅ | 질문 (`answer_count` 캐싱 포함) | 7 |
| `answers` ✅ | 답변 (`gps_verified` 포함 — 카드의 현장인증 뱃지가 이 값을 쓴다) | 7 |
| `credit_ledger` ✅ | Credit 적립·차감 내역 (통장식). 합계에서 뱃지 등급 계산 | 4·11 |
| `presences` ✅ | 누가 어느 관광지 근처에 마지막으로 있었는지. 좌표 없음(`distance_m`만), `UNIQUE(user_id, spot_content_id)`로 1인당 1행. 24시간 지난 행은 위치 신호 트랜잭션에서 함께 삭제 | 6·8 |
| `bookmarks` ✅ | 관광지 저장 (`user_id`+`spot_content_id` 유니크) | — |
| `notifications` ✅ | 인앱 알림 행(`NEW_QUESTION`/`NEW_ANSWER`, `read_at`) | 8 |
| `push_subscriptions` 🟡 | Web Push 구독 정보. **스키마만 만들어 두고 아무도 쓰지 않는다**(의도된 상태). 채널 중립 컬럼(`platform`/`endpoint`/`keys_json`) | 8(향후) |

**만들지 않기로 했거나 드롭된 테이블**

| 테이블 | 상태 |
|---|---|
| `device_tokens` / `push_jobs` / `push_log` / `motivation_texts` | ❌ **폐기** — 014에서 FCM 큐·워커 설계를 통째로 버리고 `notifications`+`push_subscriptions`로 대체 |
| `user_notification_settings` | ❌ **드롭됨** — [015](docs/worklogs/015-notification-policy-reduction.md)에서 전역 알림 토글을 없애며 마이그레이션으로 제거 |
| `briefing_cache` | ❌ **만들지 않음** — 재료 서명 기반 **메모리 캐시**로 대체(기능 10 참고) |
| `spots` | ❌ 설계 원칙 2 — TourAPI `content_id` 문자열로만 참조 |
| `activities` | ⏸ 보류 — 제보·질문·답변 통합 활동 |
| `spot_live_rollup` | ⏸ 보류 — 60초 사전계산 LIVE 수치 |
| `reviews` / `content_flags` | 리뷰는 **서버 메모리 mock**(`reviews.py`의 리스트 변수, 재시작 시 소멸). 신고(`content_flags`)는 미구현 |

⏸ **보류 2개의 이유**: 현재 규모(서울 20~30곳)에서는 매번 실시간 계산해도 체감 지연이 없다. 지금 만들면 이른 최적화다.

---

## 6. API 한눈에

**응답 필드는 `snake_case`로 통일한다.** Dart 쪽에서 `json['snake_case']` → camelCase 필드로 매핑한다. (화면이 비어 보이는 버그의 대부분이 서버↔앱 필드명 불일치였다.)

모든 경로는 `/api` prefix 아래에 있다 (`GET /spots` = `GET /api/spots`).

| 기능 | 엔드포인트 |
|---|---|
| 관광지 ✅ | `GET /spots` · `/spots/all` · `POST /spots/nearby` · `GET /spots/trending` · `GET /spots/{id}` · `/{id}/intro` · `/{id}/photos` |
| 혼잡도 ✅ | `GET /spots/{id}/congestion` · `POST /spots/congestion-batch` |
| 날씨 ✅ | `GET /spots/{id}/weather` (Open-Meteo, 실패해도 `unavailable` 응답으로 200) |
| AI 브리핑 ✅ | `GET /spots/{id}/briefing` (응답에 `source` 포함 — 404 외엔 항상 200) |
| 제보 ✅ | `POST /reports` · `GET /reports?spot_content_id=` · `GET /reports/me` |
| GPS 인증 ✅ | `POST /reports/verify-location` (응답에 `presence_registered`·`pending_questions` 포함 — 기능 6이 신규 엔드포인트 없이 여기 얹힘) |
| 알림 설정 ✅ | `GET /notifications/settings` · `GET /notifications/settings/{id}` · `POST /notifications/settings` (관광지별 제보 유도 알림. **전역 ON/OFF 토글은 015에서 제거됨**) |
| 인앱 알림 ✅ | `GET /notifications` · `GET /notifications/ws`(WebSocket) · `POST /notifications/read-all` · `POST /notifications/{id}/read` |
| LIVE ✅ | `GET /live/status/{id}`(응답에 `onsite_user_count` 포함) · `GET /live/hotspots` |
| Q&A ✅ | `POST /questions` · `GET /questions?spot_content_id=` · `GET /questions/recent` · `GET /questions/me` · `GET /questions/me/answers` · `POST /questions/{id}/answers` |
| Credit ✅ | `GET /credits/me` · `/credits/me/ledger` · `/credits/me/activity` |
| 북마크 ✅ | `POST /bookmarks` · `DELETE /bookmarks/{content_id}` · `GET /bookmarks` (추가·해제 모두 **멱등**) |
| 이미지 ✅ | `GET /images/proxy?url=` (TourAPI 이미지 CORS 중계, 호스트 화이트리스트) |
| 로그인 ✅ | `POST /auth/kakao` · `GET /auth/me` · `PUT /auth/me/nickname` · `GET /auth/nickname-available` |
| 개발용 ✅ | `GET /dev/test-users` · `POST /dev/login-as/{user_id}` (둘 다 TEST_MODE 전용) |
| 레거시 ⚠️ | `GET /spots/{id}/crowdedness` — 예측·실측을 섞던 폐기 로직. 앱 미사용, 정리 대상 |
| 레거시 ⚠️ | `POST /reviews` · `GET /reviews?spot_id=` — 서버 메모리 mock, 앱 미사용. 제보(기능 2)로 대체됐다 |
| 푸시 ⬜ | 구독 등록·해제 (`push_subscriptions` 테이블만 준비돼 있음) |

---

## 7. 남은 구현 순서

**원칙: 각 단계가 끝날 때마다 앱은 항상 정상 동작해야 한다.**

| | 단계 | 기간 | 끝나면 |
|---|---|---|---|
| ✅ | 0~3. 기반 · 제보 · LIVE · Q&A | — | **완료** |
| ✅ | 4. Credit · 뱃지 | — | **완료** — 제보 +10 / 답변 +5 실제 적립, 뱃지 등급 ([010](docs/worklogs/010-credit-badge.md)) |
| ✅ | 5. 현장 사용자 수 | — | **완료** — "최근 30분 N명" + 답변 유도 배너 ([013](docs/worklogs/013-onsite-user-count.md)) |
| ✅ | 6. AI 브리핑 | — | **완료** — Gemini 실연동, `source` 필드로 진짜 AI 표시 ([009](docs/worklogs/009-ai-briefing.md)) |
| 🟡 | 7. 푸시 | — | **인앱까지 완료** — WebSocket+폴링 알림, 대상은 `get_onsite_user_ids()` 재사용 ([014](docs/worklogs/014-question-answer-notification.md) · [015](docs/worklogs/015-notification-policy-reduction.md)). **실제 Web Push는 미착수**(웹 도달률 제약으로 후순위) |
| ✅ | 9. 로그인 (실제) | — | **완료** — 카카오 로그인 + 앱 전용 unique 닉네임, `test_user` 하드코딩 제거·다중 사용자 ([016](docs/worklogs/016-kakao-login.md) · [017](docs/worklogs/017-app-owned-unique-nickname.md)) |
| ✅ | 10. 배포 | — | **완료** — Railway에 DB·백엔드·웹앱 3개 서비스 ([012](docs/worklogs/012-railway-deploy.md)) |

**남은 단계**

| | 단계 | 기간 | 끝나면 |
|---|---|---|---|
| | A. 실제 Web Push | 2일 | 탭을 닫아도 오는 알림. `push_subscriptions` 테이블이 이미 비어 있는 채로 준비돼 있다 |
| | B. "내 주위 관광지" 보완 조회 | 1일 | `areaBasedList2` 병행 조회로 TourAPI 위치 색인 누락분 회수. **콘텐트타입 파라미터로 페이로드를 줄이는 방향으로 합의됨** ([019](docs/worklogs/019-nearby-spots-data-gap.md)) |
| | C. 운영 정비 | 2일 | 신고·제한·보관정책. 레거시 정리(`/crowdedness`, 메모리 mock `reviews`, 미사용 `feed_screen.dart`)도 여기서 |

---

## 8. 아직 결정 안 된 것

| 항목 | 권장 | 이유 |
|---|---|---|
| 질문자가 현장에 있으면 막을까? | **불허** | 곧 도착하는 사람을 막게 된다 |
| Credit 사용처를 지금 만들까? | **만들지 않는다 (확정)** | 뱃지 게이미피케이션만 가져가고, 포인트 교환·리워드 시스템은 범위 밖으로 확정 (기능 11) |
| 위치 검색에 PostGIS? | **불필요** | 현재 규모면 충분 |
| 지도 라이브러리 교체 | **후속 과제** | `dart:html`은 지원 중단 예정이고 모바일 빌드 불가 |
| 모바일 앱 전환 시점 | **미정** | 백그라운드 위치·푸시가 제대로 되려면 결국 필요 |
| 사진 업로드 파이프라인 | **미정** | `reports.photo_url` 컬럼은 이미 있다. 저장소 선택부터 필요 |
