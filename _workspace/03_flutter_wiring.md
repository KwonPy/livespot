# 03. Flutter 배선 — 날씨 배지 축소·이동(A) + 북마크(B)

기준 명세: `_workspace/01_spec.md` 2절 A/B, 5절, 6절 "프론트".
백엔드 계약 파일(`02_backend_contract.md`)은 작성 시점에 아직 없었다 — **01_spec.md의 API 계약(P-B7~P-B10)을 신뢰해 선행 구현**했다. 계약 파일이 나오면 아래 "읽는 JSON 키" 열과 문자 단위로 대조할 것.

## 화면-엔드포인트 연결표

| 화면/위젯 | 호출 메서드 | 엔드포인트 | 읽는 JSON 키 | 에러 분기 |
|---|---|---|---|---|
| `bookmarks_screen.dart` `_BookmarksScreenState.build` (FutureBuilder) | `fetchBookmarks()` | `GET /api/bookmarks` | `content_id`, `spot_name`, `spot_address`, `spot_image_url`, `created_at` | ✅ 빨간 에러 상태(원문 메시지) — 빈 상태(`[]`)와 완전히 분리 |
| `spot_detail_screen.dart` `_fetchBookmarkState` | `fetchBookmarks()` | `GET /api/bookmarks` | `content_id` (포함 여부만 판정) | 실패 시 `_bookmarked=false`로 간주(부수 기능, 화면은 살아있음). 서버가 멱등이라 오판 후 눌러도 데이터가 깨지지 않는다 |
| `spot_detail_screen.dart` `_toggleBookmark` (추가) | `addBookmark(contentId)` | `POST /api/bookmarks` body `{"content_id": "..."}` | (응답 본문 사용 안 함, 200 여부만) | ✅ 낙관적 반영 → 실패 시 롤백 + SnackBar |
| `spot_detail_screen.dart` `_toggleBookmark` (해제) | `removeBookmark(contentId)` | `DELETE /api/bookmarks/{content_id}` | (응답 본문 사용 안 함, 200 여부만) | ✅ 동일 |
| `spot_detail_screen.dart` `_fetchWeather` (기존) | `fetchWeather()` | `GET /api/weather/{content_id}` | 변경 없음 | 기존 유지 — 실패 시 배지 자리 자체가 생기지 않음 |

## A. 날씨 배지 (변경 파일 2)

- `livespot_app/lib/widgets/weather_badge.dart` — `compact` 플래그 신설(기본 `false`).
  - `compact: true` → 아이콘 `size: 10`, `fontSize: 10`, padding `h6/v2`, `borderRadius: 6`
  - `compact: false` → 기존값 그대로(`12` / `11` / `h8/v4` / `8`)
  - 위젯 기본값을 줄이지 않은 이유: `briefing_card.dart`(지도 카드)가 같은 위젯을 쓴다. **`briefing_card.dart`는 한 줄도 건드리지 않았다.**
- `livespot_app/lib/screens/detail/spot_detail_screen.dart` `_buildSliverAppBar()`
  - 배지를 `FlexibleSpaceBar.title`의 `Row`에서 **제거**하고, `background`의 `Stack`에 `Positioned`로 옮겼다.
  - 위치: `top: MediaQuery.padding.top + kToolbarHeight + 8`, `right: 16` — 액션 아이콘 줄(뒤로가기·알림·북마크) **바로 아래 우측**. 아이콘과 겹치지 않는다(P-A7).
  - `title`은 이제 단일 `Text`(Row 제거).
  - 헤더가 접히면 이미지와 함께 배지도 사라진다 — **의도된 동작**(P-A4).
  - `_weather == null`(로딩 중·조회 실패)이면 `Positioned` 자체가 트리에 없다. 에러 UI 없음(P-A5). `available:false`는 `WeatherBadge` 내부의 회색 fallback pill 그대로(P-A6).

## B. 북마크 (신규 2 / 수정 3)

**신규 `livespot_app/lib/models/bookmark_entry.dart`**

```
contentId    ← json['content_id']       String   (필수)
spotName     ← json['spot_name']        String?  (조인 실패 시 null)
spotAddress  ← json['spot_address']     String?
spotImageUrl ← json['spot_image_url']   String?
createdAt    ← json['created_at']       DateTime (_parseUtc — naive UTC에 Z를 붙여 파싱)
```

`my_report_entry.dart`의 `_parseUtc`를 그대로 복제했다. 서버가 `datetime.utcnow()` 문자열을 주므로 Z를 붙이지 않으면 9시간 어긋난다.

**수정 `livespot_app/lib/services/api_service.dart`**

- `fetchBookmarks()` → `List<BookmarkEntry>`. 200이면 파싱, 아니면 throw. **빈 배열은 정상 결과**로 통과시키고 실패만 예외로 던진다(`fetchMyReports` 규약).
- `addBookmark(contentId)` / `removeBookmark(contentId)` → 200이 아니면 throw. 서버가 멱등(P-B7/P-B8)이라 중복 탭·재시도가 에러로 보이지 않는다.

**수정 `livespot_app/lib/screens/detail/spot_detail_screen.dart`**

- 상태 필드 `bool? _bookmarked` (null = 조회 전).
- `initState`에서 `_fetchBookmarkState()` 호출 — `GET /api/bookmarks`를 받아 `contentId` 포함 여부로 판정(전용 단건 API 없음, P-B11).
- 버튼(`actions`의 두 번째 `IconButton`): `_bookmarked == true ? Icons.bookmark : Icons.bookmark_border`, 색은 알림 토글과 같은 규약(`amberAccent` / `white`). **`onPressed: _bookmarked == null ? null : _toggleBookmark`** — 상태를 모르는 동안 비활성(P-B21). 기존 `onPressed: () {}` 빈 콜백은 제거됐다.
- `_toggleBookmark()`는 `_togglePushSetting`의 복제 — 낙관적 반영 → API → 실패 시 롤백 + SnackBar(P-B20).

**신규 `livespot_app/lib/screens/profile/bookmarks_screen.dart`**

- `my_reports_screen.dart` 골격 복제: `RefreshIndicator` + `FutureBuilder`(waiting / hasError / empty / list 4분기) + `'관광지 정보 없음 (ID …)'` 폴백.
- `initState`에서 조회, 화면 진입마다 새로 호출(캐시 없음, P-B22). 상세페이지에서 돌아오면 `_refresh()`로 한 번 더 받는다.
- **해제 아이콘 없음**(P-B23). 카드 전체가 탭 영역이고 동작은 이동 하나뿐.
- 탭 → `SpotDetailScreen(spot: Spot(contentId:, title:, address:))`. 좌표 없이 진입(P-B17, `live_screen.dart` 검증된 경로). `spotName`이 null인 항목도 이동을 막지 않는다(P-B18).
- 클라이언트 재정렬 없음 — 서버가 `created_at DESC`로 준다(P-B15).
- 카드 구성: 썸네일(`spot_image_url`, 실패/없음이면 회색 placeholder) + 이름 + 주소 + `Formatters.reportRecency(createdAt)` + `chevron_right`.

**수정 `livespot_app/lib/screens/profile/profile_screen.dart`**

- 북마크 메뉴 항목에 `'onTap': _openBookmarks` 추가. 문구·서브타이틀 변경 없음, **개수 표시 없음**(P-B10a).
- `_openBookmarks()`는 push만 하고 복귀 시 `_reloadStats()`를 부르지 않는다 — 스탯에 북마크가 없고, `BookmarksScreen`이 스스로 재조회한다.

**건드리지 않은 파일**: `briefing_card.dart`, `my_reports_screen.dart`, `my_qna_screen.dart`.

## dart analyze 결과

| | 이슈 수 |
|---|---|
| 작업 전(baseline) | 73 |
| 작업 후 | 73 |

**이번 작업으로 추가된 경고/에러 0건.** 잔존 73건은 전부 기존 `withOpacity` deprecation(info)과 `avoid_print`·`depend_on_referenced_packages` 등 이번 범위 밖 항목이며, 신규 파일 2개(`bookmark_entry.dart`, `bookmarks_screen.dart`)와 수정한 4개 파일의 변경 라인에서는 한 건도 발생하지 않았다(신규 코드는 `withValues` 사용).

## contract-qa 확인 요청 사항

1. `BookmarkEntry` 5개 키의 `spot_` 접두사 — 특히 첫 키가 `content_id`(`spot_content_id` 아님)인지. `MyReportEntry`는 `spot_content_id`를 쓰므로 두 스키마가 다르다.
2. `GET /api/bookmarks`가 0건일 때 `[]`인지(404 아님).
3. `POST`/`DELETE` 응답 본문(`{"content_id","bookmarked"}`)은 앱이 사용하지 않는다 — 상태 코드 200만 본다. 멱등이 아니라 409/404를 주면 앱이 롤백 + SnackBar를 띄우므로 반드시 200이어야 한다.

---

# 이미지 CORS 프록시 적용 + HOT SPOTS 썸네일

## 문제

TourAPI 이미지 CDN(`tong.visitkorea.or.kr` 등)이 CORS 헤더를 보내지 않아, Flutter Web의 `Image.network`가 원본 URL을 그리려 하면 브라우저가 응답을 차단한다. 화면에는 아무 에러 로그 없이 `errorBuilder` 폴백(회색 placeholder)만 뜨기 때문에 **API 키나 URL이 잘못된 것처럼 보인다** — 실제 원인은 CORS다. 백엔드가 `GET /api/images/proxy?url=<원본>`을 추가했고, 앱은 원본 대신 이 프록시 URL을 그린다.

## 공통 헬퍼

`lib/utils/image_url.dart` (신규)

```dart
String? resolveImageUrl(String? rawUrl)
```

- null 또는 빈 문자열 → `null` 반환 (호출부의 placeholder 분기가 그대로 동작)
- 값이 있으면 → `'${AppConstants.apiBaseUrl}/images/proxy?url=${Uri.encodeComponent(rawUrl)}'`
- 이미 프록시 접두사로 시작하면 그대로 반환 (이중 래핑 방지)

`baseUrl`은 `AppConstants.apiBaseUrl`(`http://127.0.0.1:8000/api`)을 재사용한다 — 새로 하드코딩하지 않았다.

**규칙: 원본 이미지 URL을 `Image.network`에 직접 넘기는 코드를 새로 쓰지 않는다. 반드시 이 헬퍼를 거친다.** 현재 `lib/` 전체에 `Image.network` 호출은 4곳이며 전부 헬퍼를 거친다.

## 화면-엔드포인트 연결표 (이번 변경분)

| 화면/위젯 | 호출 메서드 | 엔드포인트 | 읽는 JSON 키 | 에러 분기 |
|---|---|---|---|---|
| `spot_detail_screen.dart:386` 헤더 이미지 | (Spot 객체 전달받음) | `GET /api/images/proxy?url=…` | — (`Spot.imageUrl`) | `errorBuilder` → `_gradientPlaceholder()` |
| `briefing_card.dart:83` 지도 카드 이미지 | (Spot 객체 전달받음) | `GET /api/images/proxy?url=…` | — (`Spot.imageUrl`) | `errorBuilder` → `_buildImagePlaceholder()` |
| `bookmarks_screen.dart:_thumbnail` 목록 썸네일 | `fetchBookmarks` | `GET /api/bookmarks` → `GET /api/images/proxy?url=…` | `spot_image_url` | `errorBuilder` → 회색 아이콘 placeholder |
| `live_screen.dart:_hotspotLeading` HOT SPOTS 썸네일 | `fetchHotspots` | `GET /api/live/hotspots` → `GET /api/images/proxy?url=…` | `content_id`, `spot_title`, `spot_address`, **`spot_image_url`(신규)**, `basis`, `display_level`, `report_count`, `last_report_at`, `congestion_rate` | 목록 조회는 ✅ 빨간 배너 / 이미지는 `errorBuilder` → 순위 `CircleAvatar` |

## 모델 변경

`lib/models/hotspot_entry.dart`

- `final String? spotImageUrl;` 추가 (nullable — 서버가 Optional)
- `fromJson`에 `spotImageUrl: json['spot_image_url'] as String?` 추가

## HOT SPOTS 카드 (`live_screen.dart`)

`ListTile.leading`을 `_hotspotLeading(spot, index + 1)`로 교체했다.

- **이미지 있음** → 44×44 둥근 사각 썸네일(프록시 URL) + **좌하단에 겹쳐 그린 18px 원형 순위 배지**(primary 배경, 흰 테두리)
- **이미지 없음 / 로딩 실패(`errorBuilder`)** → 기존 순위 `CircleAvatar` 그대로

**순위 정보는 두 경로 어디서도 사라지지 않는다.** 랭킹 목록에서 "1등인지 5등인지"가 빠지면 목록의 의미 자체가 없어지므로, 썸네일이 뜰 때도 배지로 남긴다.

## 상세페이지 진입 시 imageUrl 누락 수정

`live_screen.dart:387` — HOT SPOTS 카드 탭 시 만들던 `Spot(...)`에 `imageUrl: spot.spotImageUrl`을 추가했다. 이전에는 이 필드가 빠져 있어서 **HOT SPOTS를 거쳐 들어간 상세페이지만** 헤더 이미지가 없었다(다른 진입 경로와 달리). 프록시와 무관하게 원본부터 없던 버그다.

## null·빈 문자열 가드 정리

`spot_detail_screen.dart`와 `briefing_card.dart`의 조건이 `spot.imageUrl != null`이었는데, `resolveImageUrl`은 **빈 문자열도 null로 접기** 때문에 `imageUrl == ''`인 경우 `!` 단언이 터질 수 있었다. 조건을 `resolveImageUrl(spot.imageUrl) != null`로 바꿔 판정 기준을 한 곳으로 모았다. `bookmarks_screen.dart`는 이미 `url == null || url.isEmpty`를 검사하고 있어 그대로 뒀다.

## dart analyze 결과

| | 이슈 수 |
|---|---|
| 작업 전(baseline) | 73 |
| 작업 후 | 72 |

**이번 작업으로 추가된 이슈 0건.** 1건 감소는 `_hotspotLeading`을 새로 쓰면서 기존 `withOpacity` 호출을 `withValues(alpha:)`로 대체했기 때문이다. 잔존 72건은 전부 이번 범위 밖의 기존 항목이다(`firebase_auth` 미설치 error, `widget_test.dart`의 `MyApp` error, 미사용 import warning 2건, 나머지 `withOpacity`/`activeColor` deprecation info).

## contract-qa 확인 요청 사항

1. **프록시 쿼리 파라미터 이름이 `url`인지.** 이 작업 시점(`02_backend_contract.md` 최종 수정 09-08 18:40)에는 프록시 관련 절이 아직 없어, 지시서에 명시된 `?url=`를 그대로 따랐다. 계약서에 다른 이름(`src`, `image_url` 등)으로 적히면 `lib/utils/image_url.dart`의 `_proxyPrefix` **한 줄만** 고치면 된다.
2. **프록시 경로가 `/api/images/proxy`인지.** 앱은 `AppConstants.apiBaseUrl`(`…/api`) 뒤에 `/images/proxy`를 붙인다.
3. **인코딩 방식.** 앱은 `Uri.encodeComponent`로 원본 URL 전체를 인코딩한다(`:` `/` `?` `&` 모두 이스케이프). 백엔드가 FastAPI 쿼리 파라미터로 받으면 자동 디코딩되므로 문제없어야 하지만, 원본 URL에 이미 쿼리스트링이 붙은 경우가 있으면 실측 확인이 필요하다.
4. **`GET /live/hotspots` 응답에 `spot_image_url` 키가 실제로 있는지, 그리고 nullable인지.** 앱은 `as String?`로 캐스팅하므로 키가 아예 없어도 null이 되어 순위 `CircleAvatar` 폴백으로 떨어진다 — 즉 **조용히 실패한다.** curl 실측으로 키 존재를 확인해야 한다.
5. 프록시가 실패했을 때(원본 404, 타임아웃) 반환하는 상태 코드. 앱은 어떤 실패든 `errorBuilder` 폴백으로 처리하므로 동작에는 문제없다.
