# 명세 판정: 날씨 카드 축소·우측 정렬 + 북마크 기능

> 두 개의 독립된 수정 사항이다. A(날씨 카드)는 프론트 단독 UI 수정, B(북마크)는 신규 풀스택 기능이다.
> 서로 의존이 없으므로 병렬 구현 가능하되, **둘 다 `spot_detail_screen.dart`의 `_buildSliverAppBar()` 한 함수를 건드린다** — 같은 파일 충돌에 주의.

## 1. 범위

- 해당 기능: `function.md` **기능 12(MyPage)** 의 잔여 메뉴 "북마크" + 기능 8(날씨, [008](../docs/worklogs/008-weather-open-meteo.md)) 표시 위치 조정
- 구현 순서: `function.md` 7장의 단계표에 없는 **별건 수정**이다. 4단계(AI 브리핑)·6단계(현장 인원)와 무관하게 독립적으로 끝난다.

**이번에 만드는 것**

- (A) 관광지 상세페이지 헤더의 날씨 배지 **크기 축소 + 헤더 우측 끝 정렬**
- (B) `bookmarks` 테이블 + 마이그레이션 1건
- (B) 북마크 API 3개: `POST /api/bookmarks`(추가) · `DELETE /api/bookmarks/{content_id}`(해제) · `GET /api/bookmarks`(내 목록)
- (B) 상세페이지 우상단 북마크 버튼의 **실제 동작**(현재 `onPressed: () {}` 껍데기, `spot_detail_screen.dart:320`) — 진입 시 현재 상태 조회 → 채움/비움 아이콘 반영 → 탭 시 토글
- (B) 마이페이지 "북마크" 메뉴(현재 죽은 메뉴, `profile_screen.dart:391`) → 신규 `BookmarksScreen` 연결
- (B) 북마크 목록 항목 탭 → **해당 관광지 상세페이지로 이동**
- (B) `spot_lookup`에 목록 카드용 조회 함수 추가(제목뿐 아니라 주소·대표이미지까지)

**이번에 만들지 않는 것**

- 지도 화면 브리핑 카드(`briefing_card.dart`)의 날씨 배지 — 사용자가 "상세페이지"만 지목했다. 같은 `WeatherBadge` 위젯을 공유하므로 **위젯 기본값을 바꾸면 여기까지 같이 작아진다**(2절 P-A3 참조)
- "내 제보"·"내 Q&A" 목록의 항목 탭 → 상세 이동 — 이번 요청은 **북마크 목록에 한정**된다. 두 화면의 "탭해도 이동 안 함" 정책([function.md 기능 12])은 그대로 유지
- 북마크에 대한 Credit 적립 — 010 정책 원문("정보를 제공하거나 다른 사용자를 돕는 행동에만 보상")상 북마크는 개인 편의 행동이라 대상 아님(3절 판정)
- 북마크 폴더/태그/메모, 정렬 옵션 UI, 개수 상한
- 로그인 연동 — 프로젝트 규약대로 작성자는 전부 `deps.get_current_user_id()`

---

## 2. 확정 정책

구현자는 아래를 그대로 따른다. `contract-qa`는 이 목록을 검증 기준으로 쓴다.

### A. 날씨 카드 (프론트 단독)

| ID | 정책 | 출처 |
|---|---|---|
| P-A1 | 대상은 상세페이지 헤더의 `WeatherBadge` **하나뿐**이다(`spot_detail_screen.dart:337-339`). 상세페이지 본문에는 날씨 섹션이 따로 없다 — grep 결과 날씨 참조는 이 한 곳 | [코드] |
| P-A2 | 축소 후 치수: 아이콘 `size: 10`, 텍스트 `fontSize: 10`, padding `horizontal 6 / vertical 2`, `borderRadius: 6`. (현재 12 / 11 / 8·4 / 8) | [사용자정책] "크기를 좀 줄이는데" |
| P-A3 | 축소는 `WeatherBadge`에 **`compact` 플래그를 새로 받아** 적용한다. 위젯 내부 상수를 직접 줄이면 `briefing_card.dart:176` 부근의 지도 카드 배지까지 같이 작아진다 — 이번 범위 밖 화면이 조용히 바뀌면 안 된다 | [코드] |
| P-A4 | 배지는 **헤더 이미지 위, 액션 아이콘 줄(뒤로가기·알림·북마크) 아래의 우측 상단에 고정 배치**한다(Q1 확정: 선택지 B). 관광지명과 같은 `Row`에서 분리한다. 헤더가 접히면 이미지와 함께 배지도 사라진다 — 접힌 상태에서는 제목·액션 버튼에 폭을 양보하는 것이 008의 "날씨는 부수 정보" 취지에 맞는다. [008](../docs/worklogs/008-weather-open-meteo.md)의 "관광지명과 같은 줄" 배치는 **이번 사용자 지시로 폐기**한다 | [사용자정책, Q1=B] |
| P-A5 | 날씨 조회 실패·로딩 중에는 지금처럼 **배지 자리 자체가 생기지 않는다**. 에러 문구·SnackBar·다이얼로그를 띄우지 않는다(008 정책 원문 "날씨 영역만 fallback") | [사용자정책·과거] |
| P-A6 | `available:false` 응답은 회색 fallback pill로 계속 그린다. 이 동작을 없애지 않는다 | [코드] |
| P-A7 | 배지 위치가 어디로 가든, **헤더의 다른 요소(뒤로가기·알림·북마크 아이콘, 관광지명)와 겹치거나 잘리지 않아야 한다**. 특히 스크롤로 앱바가 접힌 상태에서 액션 아이콘 2개와 충돌하면 안 된다 | [판정] |

### B. 북마크 (풀스택)

**저장·식별**

| ID | 정책 | 출처 |
|---|---|---|
| P-B1 | 북마크는 **서버 DB에 저장**한다. `SharedPreferences` 로컬 저장은 쓰지 않는다 | [판정, 3절 쟁점 2] |
| P-B2 | 사용자 식별은 기존 체계 그대로 — `Depends(get_current_user_id)`. 즉 평소 `test_user`, `TEST_MODE`에서만 `X-Test-User-Id` 헤더로 전환. 앱은 이미 `ApiService`의 인터셉터가 헤더를 붙이므로 **앱에 추가 작업 없음**(`api_service.dart:38-43`) | [코드] |
| P-B3 | 신규 테이블 `bookmarks`. 컬럼: `id`(String(36) PK, uuid4 기본값) · `user_id`(String(36), FK `users.id`, index) · `spot_content_id`(String(20), index, **TourAPI content_id 원문 문자열**) · `created_at`(DateTime, index, default `utcnow`) | [판정, `spot_notification_settings` 선례] |
| P-B4 | `UniqueConstraint(user_id, spot_content_id, name="uq_bookmark_user_spot")` — 중복 북마크는 코드 조건문이 아니라 **DB 제약이 최종 방어선**(010 배운 것) | [판정] |
| P-B5 | 로컬 `spots` 테이블은 만들지 않는다. 관광지 정보는 캐싱하지 않고 `content_id`로만 참조한다(설계 원칙 2) | [프로젝트 규약] |
| P-B6 | 마이그레이션 1건 추가. `down_revision = '12e638fbc565'`(현재 head, credit_ledger) | [코드] |

**API 계약** — 응답 필드는 전부 `snake_case`

| ID | 정책 | 출처 |
|---|---|---|
| P-B7 | `POST /api/bookmarks` body `{"content_id": "..."}` → `200` + `{"content_id": "...", "bookmarked": true}`. **이미 북마크된 상태여도 409가 아니라 200**(멱등). 중복 탭·재시도로 화면이 에러를 띄우면 안 된다 | [판정] |
| P-B8 | `DELETE /api/bookmarks/{content_id}` → `200` + `{"content_id": "...", "bookmarked": false}`. **북마크가 없어도 404가 아니라 200**(멱등) | [판정] |
| P-B9 | `GET /api/bookmarks` → `200` + 배열. 북마크가 하나도 없으면 `[]`. **빈 상태에 404를 내지 않는다**(010 정책: 빈 상태는 에러가 아니다) | [판정] |
| P-B10 | 목록 한 줄(`BookmarkEntry`) 필드: `content_id` · `spot_name`(Optional) · `spot_address`(Optional) · `spot_image_url`(Optional) · `created_at`. `spot_*` 3개는 서버가 TourAPI에서 조인한 값이다 | [판정, `MyReportEntry` 선례] |
| P-B10a | 마이페이지 "북마크" 메뉴에는 저장 개수를 **표시하지 않는다**(Q3 확정: 선택지 A). 문구는 현행 "북마크 / 저장한 관광지" 유지. `activity` 응답 스키마도 건드리지 않는다 | [사용자정책, Q3=A] |
| P-B11 | 단건 상태 조회는 **전용 엔드포인트를 만들지 않는다.** 상세페이지는 `GET /api/bookmarks`를 받아 `content_id` 포함 여부로 판정한다. 목록 규모가 수십 건이라 별도 엔드포인트를 만들 근거가 없다 | [판정] |
| P-B12 | 북마크 등록에 **GPS 현장 인증을 요구하지 않는다.** 북마크는 "가고 싶다"의 표시이고, 현장에 없는 사람이 쓰는 기능이다(질문 작성과 같은 성격) | [판정] |
| P-B13 | 북마크에 **Credit을 지급하지 않는다.** `credit_ledger`에 행을 만들지 않고, `services/credit.py`를 한 줄도 고치지 않는다 | [사용자정책·과거, 010 9절] |
| P-B14 | 북마크는 **만료되지 않는다.** TTL·배치 정리·"오늘(KST)" 필터를 두지 않는다 | [판정] |

**목록·이동**

| ID | 정책 | 출처 |
|---|---|---|
| P-B15 | 목록 정렬은 `created_at DESC`(**최신 북마크가 위**). MyPage의 다른 모든 목록(내 제보·내 Q&A·Credit 내역)과 동일 | [코드] |
| P-B16 | 항목을 탭하면 `SpotDetailScreen(spot: Spot(contentId:, title:, address:, imageUrl:))`로 이동한다. `function.md` 기능 12의 "목록 항목을 탭해도 상세페이지로 이동하지 않는다"는 **북마크 목록에 대해서는 이번 지시로 뒤집힌다**(3절 쟁점 1) | [사용자정책] |
| P-B17 | 상세페이지 진입에 **좌표는 필요 없다.** 날씨·집중률·브리핑 전부 서버가 `content_id`로 좌표를 자체 조회한다 — HOT SPOTS 진입(`live_screen.dart:385-387`)이 이미 `Spot(contentId, title, address)`만으로 정상 동작하는 것이 증거다 | [코드] |
| P-B18 | TourAPI 조인 실패(삭제된 관광지·일시 장애)한 항목은 목록에서 **빠지지 않는다.** `spot_name`이 null로 와서 `'관광지 정보 없음 (ID xxx)'` 폴백으로 그리고, **탭 이동은 그대로 허용**한다(상세페이지가 자체적으로 다시 조회한다) | [판정, `my_reports_screen.dart:83` 선례] |
| P-B19 | 상세페이지 북마크 아이콘은 `Icons.bookmark_border`(미북마크) ↔ `Icons.bookmark`(북마크됨)로 바뀐다. 색은 알림 아이콘 토글과 같은 규약을 따른다(`spot_detail_screen.dart:308-319`) | [코드] |
| P-B20 | 토글은 **낙관적 반영 후 실패 시 롤백 + SnackBar**. `_togglePushSetting`(`spot_detail_screen.dart:183-199`)의 패턴을 그대로 따른다 | [코드] |
| P-B21 | 상태를 아직 모르는 동안(조회 전)은 버튼을 `onPressed: null`로 비활성화한다. 알림 버튼이 `_pushEnabled == null`에 대해 하는 것과 동일 | [코드] |
| P-B22 | 마이페이지에서 `BookmarksScreen`을 열고 돌아오면 목록이 다시 그려지도록, 화면 진입마다 `GET /api/bookmarks`를 새로 호출한다(캐시하지 않는다). 상세페이지에서 해제하고 돌아왔는데 옛 목록이 남는 상황을 막는다 | [판정, bug-patterns 1-3] |
| P-B23 | 북마크 목록 화면에서는 **해제 아이콘을 두지 않는다**(Q2 확정: 선택지 A). 목록은 순수 조회 + 탭 이동만 하고, 해제는 상세페이지 북마크 버튼 재탭으로만 가능하다 | [사용자정책, Q2=A] |

---

## 3. 문서 간 충돌과 판정

| 쟁점 | function.md | 지난 일지 9절 | 이번 대화 정책 | 코드 현황 | 판정 | 근거 |
|---|---|---|---|---|---|---|
| 1. MyPage 목록 항목 탭 → 상세 이동 | 기능 12: "목록 항목을 탭해도 관광지 상세페이지로 이동하지 않는다(정책 결정, 읽기 전용 이력)" | — | "북마크 목록에서 해당 관광지를 클릭하면 바로 상세페이지까지 이동" | `my_reports_screen.dart:11` 주석에 같은 정책이 박혀 있고 `onTap` 없음 | **북마크 목록은 이동한다.** 내 제보·내 Q&A는 현행 유지 | 우선순위 1(이번 대화 정책)이 이긴다. 다만 지시 범위가 "북마크 목록"으로 한정돼 있어 나머지 두 화면까지 뒤집을 근거는 없다. 성격도 다르다 — 제보/Q&A는 "내가 남긴 기록"(이력)이고 북마크는 "내가 다시 가려고 담아둔 장소"(바로가기)라, 후자는 이동이 기능의 본질이다 |
| 2. 날씨 배지 배치 | (기능 표에 배치 언급 없음) | 008 9절: "상세페이지 표시 위치 = 헤더 이미지 오버레이 배지, 새 섹션 신설 안 함" | "크기를 좀 줄이고, 가장 오른쪽 끝에 오게끔 위치도 조정" | `spot_detail_screen.dart:326-342` — 관광지명과 같은 `Row`, `MainAxisSize.min`이라 제목 **바로 뒤**에 붙는다. 코드 주석에 "관광지명과 같은 줄에 두어 항상 일직선으로 정렬한다"고 의도까지 기록돼 있다 | **우측 끝으로 옮긴다.** 008의 "헤더 오버레이"라는 큰 결정은 유지되고, 그 안에서의 정렬만 바뀐다 | 우선순위 1. 008 결정과 정면 충돌이 아니라 세부 조정이다 — 새 섹션을 만드는 게 아니라 헤더 안에서 위치만 옮기는 것이라 008의 근거("섹션 순서를 밀지 않는다")를 훼손하지 않는다 |
| 3. MyPage 스탯 카드의 북마크 자리 | 기능 12 표에 스탯 4칸 명시 없음 | 010: "동작하지 않던 '북마크' 자리를 뱃지로 교체했다"(코드 주석 `profile_screen.dart:291`) | (언급 없음) | 스탯 4칸 = 제보/답변/Credit/**뱃지** | **뱃지 칸을 되돌리지 않는다.** 북마크 개수를 스탯 칸에 넣지 않는다 | 010에서 의도적으로 교체한 자리다. 사용자는 "mypage의 북마크 **목록**"만 요구했고 스탯 표시는 요구하지 않았다. 다만 메뉴 subtitle에 개수를 넣을지는 미결정(Q3) |
| 4. 북마크 = 죽은 메뉴 | 24행: "알림 설정·위치 권한·계정(로그아웃)·북마크는 아직 죽은 메뉴" | — | "북마크기능 추가야!" | `profile_screen.dart:391` — `onTap` 키 자체가 없어 리플도 안 뜬다. `spot_detail_screen.dart:320` — `onPressed: () {}` 빈 콜백 | **둘 다 실제 동작으로 채운다.** 완료 후 `function.md` 24행의 "북마크"는 죽은 메뉴 목록에서 빠져야 한다 | 문서가 낡게 되는 지점 — `journal-keeper`가 일지에 남기고 function.md 현황표도 갱신 대상이다 |
| 5. 상세페이지 북마크 버튼의 빈 콜백 | — | — | — | `onPressed: () {}` — 누르면 리플만 뜨고 아무 일도 없다. 알림 버튼과 달리 "죽었음"이 사용자에게 드러나지 않는 상태 | 이번에 제거된다 | 코드 쪽이 명백한 미완성이라 판정 불필요 |
| 6. 응답 필드 표기 | 6장 "snake_case로 통일" | — | — | 전부 snake_case | **snake_case** (5장의 camelCase 문장은 이미 폐기 판정됨) | 프로젝트 규약 |

---

## 4. 미결정 사항 (리더가 사용자에게 확인할 것)

### Q1. 날씨 배지를 헤더의 "오른쪽 끝" 어디에 둘 것인가

- 맥락: 상세페이지 헤더는 스크롤에 따라 접히는 `SliverAppBar`다. 오른쪽 끝 위쪽에는 이미 액션 아이콘 2개(알림 종, 북마크)가 있고, 이번 작업으로 북마크 아이콘이 실제로 동작하게 되면서 그 자리의 중요도가 올라간다. "오른쪽 끝"을 어느 높이에 두느냐에 따라 **접혔을 때 아이콘과 겹치거나, 아예 사라지거나** 한다. 되돌리기가 비싸진 않지만 세 안의 체감이 꽤 다르다.
- 선택지 A: **관광지명과 같은 줄, 오른쪽 끝으로 밀기** (제목을 `Expanded`로 늘리고 배지를 행 끝에 배치) → 접혀도 배지가 계속 보이고 제목과 한 줄에 정렬된다. 다만 접힌 상태에서는 이 줄이 액션 아이콘 2개 왼쪽까지만 쓸 수 있어, 배지가 아이콘 바로 옆에 딱 붙어 다소 빽빽해 보인다.
- 선택지 B: **헤더 이미지 위, 액션 아이콘 줄 아래의 우측 상단에 고정 배치** → 아이콘과 확실히 분리돼 가장 깔끔하고 "오른쪽 끝"이라는 지시에 가장 충실하다. 대신 헤더가 접히면 이미지와 함께 **배지도 사라진다**(지금은 제목과 함께 남아 있다).
- 선택지 C: **헤더 이미지의 우측 하단**(관광지명과 같은 높이의 반대편 끝) → 제목과 좌우로 나뉘어 균형이 좋고 아이콘과도 안 겹친다. 접히면 B와 마찬가지로 사라진다.
- 권장: **B**. 지시의 "가장 오른쪽 끝"에 가장 정확하고, 008에서 날씨를 "부수 정보"로 규정했으므로 접혔을 때 사라지는 것이 오히려 정책에 맞는다(접힌 헤더의 좁은 폭은 제목과 동작 버튼에 양보). 접힘 후에도 기온이 계속 보여야 한다면 A.

### Q2. 마이페이지 북마크 목록에서 북마크를 해제할 수 있어야 하는가

- 맥락: 사용자 지시에는 "추가"와 "클릭 시 이동"만 있고 해제 경로가 언급되지 않았다. 상세페이지 버튼 재탭으로 해제는 되지만, 그러려면 지우려는 관광지의 상세페이지에 매번 들어가야 한다. 목록에서 바로 지울 수 있게 하려면 **탭 = 이동**과 **삭제 제스처**가 한 항목에 공존해야 해서, 나중에 붙이면 카드 레이아웃을 다시 짜야 한다.
- 선택지 A: **상세페이지에서만 해제.** 목록은 순수한 읽기 + 이동 → 구현이 가장 단순하고 탭 동작이 하나뿐이라 오조작이 없다. 대신 북마크가 20~30개 쌓이면 정리가 번거롭다.
- 선택지 B: **목록 항목 우측에 북마크 해제 아이콘 버튼 추가** → 한 번에 지운다. 탭 영역이 둘로 나뉘어(카드=이동, 아이콘=해제) 좁은 화면에서 오탭 여지가 생긴다.
- 선택지 C: **스와이프 삭제(`Dismissible`) + 실행취소 SnackBar** → 목록 화면의 표준 관용구이고 오탭이 적다. 웹앱(Flutter Web)에서 마우스 드래그로 스와이프하는 조작은 모바일만큼 자연스럽지 않다는 점이 걸린다.
- 권장: **B**. 이 앱은 웹 실행이 기본이라 스와이프(C)의 발견 가능성이 낮고, A는 "담기는 쉬운데 빼기는 어렵다"는 비대칭을 만든다. 아이콘 자리를 처음부터 잡아두면 나중에 카드를 다시 짜지 않아도 된다.

### Q3. 마이페이지 "북마크" 메뉴에 저장 개수를 표시할 것인가

- 맥락: 현재 메뉴 줄은 `북마크 / 저장한 관광지`라는 고정 문구다. 개수를 보여주려면 마이페이지가 **화면 진입 시점에 북마크를 한 번 더 조회**해야 한다(지금은 크레딧·활동 2건만 조회). 나중에 붙이려면 조회·로딩·실패 처리를 그때 또 설계해야 한다.
- 선택지 A: **표시하지 않는다.** 지금 문구 그대로 → 마이페이지 조회 부하와 코드가 그대로다. 사용자는 목록에 들어가 봐야 몇 개인지 안다.
- 선택지 B: **`GET /api/credits/me/activity` 응답에 `bookmark_count`를 추가**해 기존 조회에 얹는다 → 네트워크 요청이 늘지 않고 스켈레톤·에러 배너도 이미 있는 것을 그대로 쓴다. 다만 "활동 건수"(제보·답변·질문 = 남에게 기여한 행동)라는 이 응답의 의미에 개인 행동인 북마크가 섞인다.
- 선택지 C: **마이페이지에서 `GET /api/bookmarks`를 따로 호출**해 개수만 센다 → 의미가 섞이지 않는다. 대신 목록 전체를 받아 개수만 쓰는 낭비이고, 마이페이지 조회가 3건으로 늘면서 실패 조합이 하나 더 생긴다.
- 권장: **A**. 이번 지시에 없는 항목이고, 개수는 목록에 들어가면 바로 보인다. 나중에 원하면 B로 얹는 것이 가장 싸다(엔드포인트 신설 없이 필드 하나 추가).

---

## 5. 재사용 가능한 기존 자산

| 파일:라인 | 무엇 | 어떻게 쓰나 |
|---|---|---|
| `livespot_backend/app/db/models/notification_setting.py:10-25` | `user_id` + `spot_content_id` + UNIQUE 조합 테이블의 **완성된 선례** | `bookmarks` 모델의 골격을 그대로 베낀다. 컬럼 타입(String(36)/String(20))·인덱스·UNIQUE 이름 규칙까지 동일하게 |
| `livespot_backend/app/api/notifications.py:14-73` | 같은 형태 테이블의 조회·목록·upsert 라우터 | 북마크 라우터의 쿼리 패턴(`select(...).where(user_id, spot_content_id)`)을 그대로 |
| `livespot_backend/app/api/deps.py:10-25` | `get_current_user_id` | 모든 북마크 엔드포인트에 `Depends`로. 새 인증 코드를 쓰지 않는다 |
| `livespot_backend/app/services/spot_lookup.py:16-34` | `resolve_spot_names(content_ids) → {id: title}`, TourAPI 10분 캐시 재사용, 실패 시 조용히 누락 | **함수를 새로 하나 추가**한다(예: `resolve_spot_cards`) — 북마크 카드는 title 외에 `addr1`·`firstimage`도 필요한데 기존 함수 반환형을 바꾸면 `reports.py`·`questions.py`가 같이 깨진다. 내부의 `get_spot_detail` 캐시는 그대로 공유되므로 추가 API 비용은 사실상 없다 |
| `livespot_backend/app/api/spots.py:59-72` (`parse_spot_detail`) | TourAPI 원본 키 → snake_case 매핑(`contentid`→`content_id`, `addr1`→`address`, `firstimage`→`image_url`) | 조인 필드를 만들 때 이 키 매핑을 그대로 따른다. TourAPI 키 이름을 새로 추측하지 말 것 |
| `livespot_backend/app/api/reports.py:135-160` | `GET /me` 목록 + `resolve_spot_names` 조인 + 최신순 정렬의 완성형 | `GET /api/bookmarks` 구현을 이 함수 구조대로 |
| `livespot_backend/app/models/schemas.py:359-371` (`MyReportEntry`) | `spot_content_id` + `spot_name: Optional` 조인 스키마 | `BookmarkEntry` 스키마의 본. `spot_*` 접두사 규칙을 유지 |
| `livespot_backend/migrations/versions/12e638fbc565_*.py` | 현재 head 리비전 | 새 마이그레이션의 `down_revision` |
| `livespot_app/lib/services/api_service.dart:38-43` | `X-Test-User-Id` 자동 첨부 인터셉터 | 북마크 API 호출에 별도 헤더 코드 불필요 |
| `livespot_app/lib/services/api_service.dart:359-367` (`fetchMyReports`) | MyPage 목록 조회 메서드의 예외 처리 규약(빈 배열과 실패를 구분, 실패는 반드시 throw) | `fetchBookmarks` / `addBookmark` / `removeBookmark`를 같은 규약으로 |
| `livespot_app/lib/screens/detail/spot_detail_screen.dart:183-199` (`_togglePushSetting`) | 낙관적 반영 → 실패 시 롤백 → SnackBar 토글의 완성형 | 북마크 토글을 이 함수의 복제로 |
| `livespot_app/lib/screens/detail/spot_detail_screen.dart:308-319` | 상태에 따라 아이콘·색이 바뀌는 `CircleAvatar` 액션 버튼 | 북마크 버튼(`:320`)을 이 형태로 교체 |
| `livespot_app/lib/screens/profile/my_reports_screen.dart` 전체 | MyPage 목록 화면의 표준 골격(FutureBuilder + RefreshIndicator + 빈 상태 + 에러 상태 + `'관광지 정보 없음 (ID …)'` 폴백) | `BookmarksScreen`의 뼈대. **새로 설계하지 말 것** |
| `livespot_app/lib/screens/live/live_screen.dart:382-389` | 좌표 없이 `Spot(contentId, title, address)`만으로 상세페이지 진입 — 이미 검증된 경로 | 북마크 목록 → 상세 이동을 이 방식으로 |
| `livespot_app/lib/screens/profile/profile_screen.dart:443-449` (`_openCreditLedger`) | 하위 화면 push 후 복귀 시 갱신 | 북마크 메뉴의 `onTap` |
| `livespot_app/lib/widgets/weather_badge.dart:64-97` | 배지 렌더링 본체 | `compact` 플래그를 추가해 치수만 분기(P-A3) |

---

## 6. 영향 범위

**백엔드**

- 신규 `livespot_backend/app/db/models/bookmark.py`
- 수정 `livespot_backend/app/db/models/__init__.py` — 모델 등록(누락 시 마이그레이션 자동생성·메타데이터에서 빠진다)
- 신규 `livespot_backend/app/api/bookmarks.py`
- 수정 `livespot_backend/app/api/router.py` — `include_router(bookmarks.router, prefix="/bookmarks", tags=["bookmarks"])`
- 수정 `livespot_backend/app/models/schemas.py` — `BookmarkCreate`, `BookmarkToggleResponse`, `BookmarkEntry`
- 수정 `livespot_backend/app/services/spot_lookup.py` — 카드용 조회 함수 추가(기존 함수는 **변경 금지**)
- 신규 `livespot_backend/migrations/versions/*_add_bookmarks_table.py` (`down_revision='12e638fbc565'`)
- **건드리지 않는다**: `services/credit.py`, `api/credits.py`, `api/reports.py`, `api/questions.py`

**프론트**

- 수정 `livespot_app/lib/widgets/weather_badge.dart` — `compact` 플래그 (A)
- 수정 `livespot_app/lib/screens/detail/spot_detail_screen.dart` — 헤더 날씨 배치(A) + 북마크 상태 조회·토글·아이콘(B). **A와 B가 같은 `_buildSliverAppBar()`를 고친다**
- 신규 `livespot_app/lib/models/bookmark_entry.dart`
- 수정 `livespot_app/lib/services/api_service.dart` — `fetchBookmarks` / `addBookmark` / `removeBookmark`
- 신규 `livespot_app/lib/screens/profile/bookmarks_screen.dart`
- 수정 `livespot_app/lib/screens/profile/profile_screen.dart` — 북마크 메뉴에 `onTap` 연결
- **건드리지 않는다**: `briefing_card.dart`(지도 카드 날씨), `my_reports_screen.dart`, `my_qna_screen.dart`

**마이그레이션 필요 여부: yes** — `bookmarks` 테이블 1건 추가. 기존 테이블 변경 없음(파괴적 변경 아님).

**경계면 검증 포인트** (`contract-qa`용)

1. `BookmarkEntry`의 5개 키(`content_id` / `spot_name` / `spot_address` / `spot_image_url` / `created_at`)가 Dart `fromJson`이 읽는 키와 정확히 일치하는가 — 특히 `spot_` 접두사 유무
2. 북마크 0건일 때 `[]`가 오고 앱이 빈 상태 화면을 그리는가(에러 화면이 아니라)
3. 같은 관광지를 두 번 POST해도 200이고 DB 행이 1개인가
4. `X-Test-User-Id`를 바꾸면 북마크 목록이 실제로 갈라지는가
5. 목록 → 상세 이동 후 날씨·집중률·브리핑이 정상 표시되는가(좌표 없이 진입해도 서버가 조회하므로 동작해야 함)
