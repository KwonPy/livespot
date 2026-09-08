# QA 리포트 — 날씨 배지 축소·이동(A) + 북마크(B) (검증 1회차)

검증 시각: 2026-09-08 18:4x / 서버 `127.0.0.1:8000` 기동 상태(재기동 불필요, `/health` → `{"status":"ok"}`)
기준: `_workspace/01_spec.md` 2절 확정 정책. 대조 대상: `02_backend_contract.md`, `03_flutter_wiring.md` + 양쪽 실제 소스.

## 판정 요약

| 항목 | 통과 | 실패 | 관찰(수정 권고) | 미검증 |
|---|---|---|---|---|
| 1. `BookmarkEntry` 5키 교차 대조 | ✅ | | | |
| 2. 빈 배열 `[]` + 앱 빈 상태 분기 | ✅ | | | |
| 3. POST/DELETE 멱등성 (curl 실측) | ✅ | | | |
| 4. P-B18 TourAPI 조인 실패 폴백 | ✅ | | | |
| 5. 목록→상세 이동, `Spot()` 인자 정합 | ✅ | | O-1 (`imageUrl` 미전달) | |
| 6. `compact` 플래그 격리(`briefing_card` 무영향) | ✅ | | | |
| 7. `dart analyze` 신규 이슈 0건 | ✅ | | | |
| 8. Credit 미지급 (`credit.py` 무수정) | ✅ | | | |
| — | | | | 사용자 격리(임의 헤더) — 아래 미검증란 참조 |

**실패(FAIL) 0건.** 수정 권고 1건(경미, 기능 결함 아님).

---

## 항목별 근거

### 1. `BookmarkEntry` 키 교차 — PASS

curl 실측 최상위 키:
```
['content_id', 'created_at', 'spot_address', 'spot_image_url', 'spot_name']
```

Dart `livespot_app/lib/models/bookmark_entry.dart:34-38`:
```dart
contentId:    json['content_id']     as String,
spotName:     json['spot_name']      as String?,
spotAddress:  json['spot_address']   as String?,
spotImageUrl: json['spot_image_url'] as String?,
createdAt:    _parseUtc(json['created_at'] as String),
```

- 5/5 문자 단위 일치. `MISSING` 없음, `UNREAD` 없음.
- **backend-builder가 경고한 지점 재확인**: 첫 키는 `content_id`다. Dart도 `json['content_id']`를 읽는다(`spot_content_id` 오염 없음). `MyReportEntry`(`spot_content_id`) 복사 사고는 발생하지 않았다.
  - 서버 측 근거: `schemas.py:425` `content_id: str`, `bookmarks.py:98` `content_id=b.spot_content_id` — DB 컬럼명(`spot_content_id`)과 응답 키(`content_id`)를 라우터에서 명시적으로 갈랐다.
- Nullable 정합: `schemas.py:426-428` `Optional[str] = None` 3개 ↔ Dart `as String?` 3개. non-null 캐스팅 없음. `content_id`/`created_at`은 서버 non-null ↔ Dart non-null. `?? 기본값`으로 실패를 숨긴 곳 없음.
- datetime: 서버 실측 `"2026-09-08T09:39:39.961484"` (naive UTC, Z 없음). Dart `bookmark_entry.dart:3-6` `_parseUtc`가 Z를 붙여 파싱 — 9시간 오차 없음. **PASS**
- 중첩 객체 없음(평평한 배열) — 확인.

### 2. 빈 배열 + 앱 빈 상태 — PASS

```
$ curl -s -w " HTTP:%{http_code}" -H "X-Test-User-Id: seed_user_02" http://127.0.0.1:8000/api/bookmarks
[] HTTP:200
```
404 아님. 앱 `bookmarks_screen.dart:71-81` 4분기 확인:
```dart
if (snapshot.connectionState == ConnectionState.waiting) ... // 로딩
if (snapshot.hasError) return _errorState(snapshot.error);   // 에러 — 빨간 화면
final bookmarks = snapshot.data ?? [];
if (bookmarks.isEmpty) return _emptyState();                 // 빈 상태 — 회색 안내
```
`hasError`가 **별도 분기**이고 빈 상태(`_emptyState`, 회색 북마크 아이콘)와 에러 상태(`_errorState`, 빨간 아이콘 + 원문 메시지)의 화면이 서로 다르다. HOT SPOTS 때의 "에러를 빈 상태로 뭉갬" 패턴 재발 없음. `api_service.dart:397-404`도 빈 배열은 정상 통과, 비200만 throw.

### 3. 멱등성 — PASS (curl 실측, `seed_user_02`)

| 호출 | 응답 | HTTP |
|---|---|---|
| POST 126508 (최초) | `{"content_id":"126508","bookmarked":true}` | 200 |
| POST 126508 (재전송) | `{"content_id":"126508","bookmarked":true}` | **200** |
| DELETE 126508 | `{"content_id":"126508","bookmarked":false}` | 200 |
| DELETE 126508 (재전송) | `{"content_id":"126508","bookmarked":false}` | **200** |
| DELETE 111111 (한 번도 북마크 안 함) | `{"content_id":"111111","bookmarked":false}` | **200** |

409/404/400 한 건도 발생하지 않음. `bookmarks.py:47-52`가 존재 확인 + `IntegrityError` 이중 방어. 테스트 후 DB 행 원상복구 확인(`bookmarks` 2행 = 스모크 데이터 그대로).

### 4. P-B18 폴백 — PASS

존재하지 않는 `999999999`를 북마크한 뒤의 실측 응답 — **목록에서 빠지지 않는다**:
```json
{"content_id":"999999999","spot_name":null,"spot_address":null,"spot_image_url":null,"created_at":"2026-09-08T09:42:42.847642"}
```
앱 폴백 렌더링 대조:
- 제목: `bookmarks_screen.dart:118` `b.spotName ?? '관광지 정보 없음 (ID ${b.contentId})'` → `'관광지 정보 없음 (ID 999999999)'`
- 주소: `:123` `if (b.spotAddress != null && b.spotAddress!.isNotEmpty)` → 줄 자체가 생기지 않음
- 썸네일: `:159` `url == null || url.isEmpty ? placeholder()` → 회색 placeholder. 서버가 빈 문자열을 None으로 정규화하므로(`spot_lookup.py::_clean`) 깨진 이미지 자리 없음
- 탭 이동: `:106` `onTap: () => _openSpot(b)` — null 여부로 막지 않음. **이동 허용 확인**

### 5. 목록 → 상세 이동 / `Spot()` 인자 — PASS (권고 O-1)

`bookmarks_screen.dart:48-55`:
```dart
SpotDetailScreen(spot: Spot(contentId: b.contentId, title: ..., address: b.spotAddress))
```
`lib/models/spot.dart` 생성자: `contentId`(required) / `title`(required) / `address`(optional named) — **인자명·필수성 전부 일치, 좌표 없이 생성 가능**. `live_screen.dart:386`의 검증된 경로와 동일 형태. 복귀 시 `:58` `_refresh()`로 재조회(P-B22 충족).

→ **O-1 (권고, 심각도: 낮음 / 기능 결함 아님)** 아래 별도 절 참조.

### 6. `compact` 격리 — PASS

- `weather_badge.dart:20` `final bool compact;` / `:26` `this.compact = false` — **기본값 false**
- 치수 분기는 전부 삼항: padding `h6/v2` vs `h8/v4`, radius `6:8`, icon `10:12`, fontSize `10:11` — 위젯 내부 상수를 줄인 곳 없음
- `briefing_card.dart:137` `WeatherBadge(weather: weather)` — `compact` 미전달 → false → **지도 화면 배지 치수 변화 0**. `briefing_card.dart`에 `compact` 문자열 자체가 존재하지 않음
- `spot_detail_screen.dart:402` `WeatherBadge(weather: _weather!, onImage: true, compact: true)` — 상세페이지에서만 true
- 배치(P-A4/A7): `:398-403` `if (_weather != null) Positioned(top: MediaQuery.padding.top + kToolbarHeight + 8, right: 16)` — 액션 아이콘 줄 아래 우측. `FlexibleSpaceBar.background`의 `Stack` 안이라 접히면 사라짐(의도된 동작). `title`은 단일 `Text`로 Row 제거 확인
- P-A5: `_weather == null`이면 `Positioned` 자체가 트리에 없음 — 에러 문구·SnackBar 없음. P-A6: `WeatherBadge:60` `unavailable` 회색 pill 경로 그대로 살아 있음

### 7. `dart analyze` — PASS (독립 재실행)

```
73 issues found.
```
builder 보고(작업 후 73)와 일치. 변경/신규 파일별 실제 히트:
- `bookmark_entry.dart` — **0건**
- `bookmarks_screen.dart` — **0건**
- `weather_badge.dart` — **0건**
- `spot_detail_screen.dart` — 4건, 전부 `withOpacity` deprecation(라인 483/621/857/890 — 북마크·날씨 변경 라인 아님)
- `profile_screen.dart` — 5건, 전부 `withOpacity`(191/199/258/404/415 — `_openBookmarks`·메뉴 라인 아님)
- `api_service.dart` — 2건, `avoid_print`(77/91 — 인터셉터, 기존 코드)

**이번 기능으로 추가된 이슈 0건 확인.** 신규 코드는 `withValues` 사용(`bookmarks_screen.dart:100`).

### 8. Credit 미지급 — PASS

- `app/api/bookmarks.py` 전문에 `credit` / `CreditLedger` / `award_credit` 문자열 **0건**
- `app/services/spot_lookup.py`도 동일
- 파일 mtime: `services/credit.py` **12:29**, `api/credits.py` **12:29**, `api/reports.py`·`api/questions.py` **14:42** — 북마크 작업 시각(`bookmarks.py` 18:37, `schemas.py` 18:36)보다 이전. **명세 6절 "건드리지 않는다" 4개 파일 전부 무수정**
- 런타임 실측: 북마크 POST 3회 전후 `credit_ledger` 행 수 **18 → 18** (변화 없음)
- `spot_lookup.py`의 기존 `resolve_spot_names()`는 그대로 두고 `resolve_spot_cards()`를 **추가**(`:37`) — `reports.py`/`questions.py` 회귀 위험 없음

### 부수 확인 (요청 외, 경계면 필수 항목)

- **경로·등록**: `router.py:14` `include_router(bookmarks.router, prefix="/bookmarks", ...)` 등록됨. `constants.dart:2` baseUrl `http://127.0.0.1:8000/api` + `_dio.get('/bookmarks')` = `/api/bookmarks` — 실제 curl 200으로 확인. 404 없음
- **응답 래핑**: 서버 `response_model=List[BookmarkEntry]` ↔ Dart `final List<dynamic> data = response.data` (`api_service.dart:400`) — 리스트↔리스트 일치. POST/DELETE는 객체이나 앱이 본문을 쓰지 않음
- **P-B11**: 단건 조회 엔드포인트 없음 ↔ `spot_detail_screen.dart:209-213`가 목록을 받아 `bookmarks.any((b) => b.contentId == widget.spot.contentId)`로 판정 — 규약대로
- **P-B21**: `spot_detail_screen.dart:373` `onPressed: _bookmarked == null ? null : _toggleBookmark` — 조회 전 비활성. 기존 `onPressed: () {}` 빈 콜백 제거됨
- **P-B19/B20**: `:366-367` 아이콘·색 토글, `:220-239` 낙관적 반영 → 실패 시 `setState(() => _bookmarked = !next)` 롤백 + SnackBar
- **P-B23**: `bookmarks_screen.dart`에 해제 아이콘·`Dismissible` 없음. 탭 동작은 `_openSpot` 하나뿐
- **P-B10a**: `profile_screen.dart:392` subtitle `'저장한 관광지'` 고정, 개수 없음. `_openBookmarks`(`:446-450`)가 복귀 시 `_reloadStats()` 미호출 — 스탯 스키마 무변경
- **P-B15**: `bookmarks.py:92` `order_by(Bookmark.created_at.desc())` ↔ curl 실측 최신이 위. 앱에 재정렬 코드 없음
- **P-B12/B14**: 라우터에 GPS 검증·TTL·"오늘(KST)" 필터 없음

---

## 실패 (수정 필요)

**없음.**

---

## 관찰 · 수정 권고

### O-1. 북마크 목록에 이미 있는 대표이미지를 상세페이지로 넘기지 않는다 — [심각도: 낮음 / 기능 결함 아님]

- 경계면: `livespot_app/lib/screens/profile/bookmarks_screen.dart:48-55` ↔ `livespot_app/lib/screens/detail/spot_detail_screen.dart:385-387`
- 증거:
  ```dart
  // bookmarks_screen.dart:49-53
  spot: Spot(
    contentId: b.contentId,
    title: b.spotName ?? '관광지 정보 없음 (ID ${b.contentId})',
    address: b.spotAddress,          // ← imageUrl 없음
  ),
  ```
  ```dart
  // spot_detail_screen.dart:385-387 — 헤더 이미지는 widget.spot.imageUrl만 본다
  widget.spot.imageUrl != null ? Image.network(widget.spot.imageUrl!, ...) : _gradientPlaceholder()
  ```
  `_fetchExtraInfo()`가 받아오는 `_spotDetail`은 헤더 이미지에 쓰이지 않는다(grep 결과 헤더는 `widget.spot.imageUrl` 단일 소스).
- 명세 대조: `01_spec.md` P-B16은 `Spot(contentId:, title:, address:, imageUrl:)`로 **`imageUrl`을 포함해** 명시한다. `03_flutter_wiring.md:60`은 3개만 적었다 — 문서끼리도 어긋난다.
- 결과: 목록 카드에서는 썸네일이 보였는데, 그 항목을 탭해 들어간 상세페이지 헤더는 **회색 그라데이션 placeholder**로 뜬다. 데이터를 이미 손에 쥐고 있으면서 안 쓰는 상황이라 사용자 눈에는 "왜 여기만 사진이 없지"로 보인다. (기능·통신은 정상 — 순수 시각 손실)
- 참고: `live_screen.dart:386`도 `imageUrl`을 안 넘기지만 그쪽은 **애초에 URL이 없다**(`HotspotEntry`에 이미지 필드 없음). 북마크는 `spot_image_url`을 받아 놓고 버리는 것이라 성격이 다르다.
- 수정 대상: **flutter-builder**
- 수정 방법: `bookmarks_screen.dart:53` `address: b.spotAddress,` 다음 줄에 `imageUrl: b.spotImageUrl,` 한 줄 추가. `Spot` 생성자에 이미 optional named `imageUrl`이 있어 다른 변경 불필요.

---

## 미검증 항목과 이유

### U-1. 사용자 격리 (명세 6절 경계면 검증 포인트 4) — 부분 검증

- 검증된 것: `seed_user_02` 헤더로 POST/DELETE/GET한 결과가 기본 사용자 목록(`['132215','126508']`)에 **전혀 영향을 주지 않음**을 실측 확인. UNIQUE는 `(user_id, spot_content_id)` 조합이므로 사용자별 분리 동작 확인.
- 검증 못 한 것: `X-Test-User-Id`에 **DB에 없는 임의 문자열**(`qa_empty_user_zz`)을 넣으면 헤더가 무시되고 기본 사용자 목록이 그대로 온다.
  - 원인은 북마크가 아니라 `livespot_backend/app/api/deps.py:21-25` — `db.get(User, x_test_user_id)`가 None이면 `TEST_USER_ID`로 폴백하는 **기존 공통 동작**이다. 북마크 기능이 만든 결함이 아니므로 FAIL로 잡지 않는다. 다만 `02_backend_contract.md`의 격리 실측표를 읽는 사람이 "아무 헤더나 넣으면 갈라진다"고 오해할 수 있어 여기 기록해 둔다.

### U-2. 실제 앱 화면 렌더링 — 미검증

`flutter run`은 이 검증 범위에서 하지 않는다(규약). 아래는 **코드 경로만** 확인했고 눈으로 본 것이 아니다:
- 날씨 배지가 접힌 앱바에서 액션 아이콘과 실제로 안 겹치는지(P-A7) — `Positioned` 좌표 계산상 겹치지 않으나 실측 스크린샷 없음
- 축소된 배지의 가독성(fontSize 10)
- 북마크 목록 카드의 실제 레이아웃 오버플로 여부

→ 사용자 구동 확인 항목으로 남긴다.

---

## 실행 검증 결과

- **uvicorn 기동**: 성공(기존 프로세스 생존). `GET /health` → `{"status":"ok"}`
- **curl 실측 (엔드포인트별)**
  | 엔드포인트 | HTTP | 응답 최상위 키 |
  |---|---|---|
  | `GET /api/bookmarks` (2건) | 200 | `['content_id','created_at','spot_address','spot_image_url','spot_name']` |
  | `GET /api/bookmarks` (0건) | 200 | `[]` (빈 배열, 404 아님) |
  | `POST /api/bookmarks` | 200 | `['content_id','bookmarked']` |
  | `DELETE /api/bookmarks/{id}` | 200 | `['content_id','bookmarked']` |
  | `POST` 재전송 / `DELETE` 재전송 / 없는 id `DELETE` | 200 / 200 / 200 | 동일 (멱등 확인) |
- **DB 실측**: `bookmarks` 테이블 테스트 전후 2행 유지, `credit_ledger` 18행 유지(북마크가 크레딧을 쓰지 않음)
- **dart analyze**: **73 issues** (baseline 73과 동일, 신규 0건)

---

## 다음 회차에서 재확인할 것

- O-1 반영 여부(`bookmarks_screen.dart`에 `imageUrl: b.spotImageUrl` 추가)
- 그 외 항목은 재발 감시 대상 없음(1회차 FAIL 0건)

---

## 2회차 (리더 직접 반영, 2026-09-08)

O-1을 리더가 직접 수정했다 — 팀원 재소집 없이 처리해도 되는 1줄 수정으로 판단.

`bookmarks_screen.dart:49-53`:
```dart
spot: Spot(
  contentId: b.contentId,
  title: b.spotName ?? '관광지 정보 없음 (ID ${b.contentId})',
  address: b.spotAddress,
  imageUrl: b.spotImageUrl,   // 추가
),
```

`Spot` 생성자(`lib/models/spot.dart`)에 이미 있는 optional named `imageUrl`을 그대로 사용, 다른 변경 없음.
검증: `dart analyze lib/screens/profile/bookmarks_screen.dart` → **No issues found!**

**최종 판정: FAIL 0건, 미해결 0건.** 남은 것은 U-1(북마크 기능 결함 아님, 기존 `deps.py` 공통 동작 기록용)과 U-2(실제 화면 렌더링, 사용자 구동 확인 항목)뿐이다.

---

# QA 리포트 — 이미지 CORS 프록시 + HOT SPOTS 대표이미지 (검증 3회차)

> 대상: `02_backend_contract.md` 하단 새 절(`GET /api/images/proxy`, `HotspotEntry.spot_image_url`) ↔ `03_flutter_wiring.md` 하단 새 절(`resolveImageUrl()`, `_hotspotLeading`).
> 서버: 127.0.0.1:8000 기동 확인 (`{"status":"ok"}`). 아래 수치는 전부 이번 회차 실측 원문이다.
> 인코딩 재현 방식: Dart `Uri.encodeComponent`의 unreserved 집합(`A-Za-z0-9 - _ . ! ~ * ' ( )`)을 그대로 쓴 Python `quote(url, safe="-_.!~*'()")`로 **앱이 만드는 것과 문자 단위로 동일한 URL**을 생성해 호출했다.

## 판정 요약

| 항목 | 통과 | 실패 | 미검증 |
|---|---|---|---|
| 1. 프록시 화이트리스트 실제 대조 | O | | |
| 2. `Uri.encodeComponent` 인코딩 + 헤더 | O | | |
| 3. SSRF 방지 | O | | |
| 4. `HotspotEntry` 키 문자 단위 대조 | O | | |
| 5. HOT SPOTS → 상세 이미지 전달(원본 여부) | O | | |
| 6. 빈 문자열 정규화 이중 안전 | O (관찰 O-1) | | |
| 7. `flutter analyze` 추가 이슈 | O 0건 | | |
| 8. 실제 이미지 바이트 반환 | O | | |
| REPORT 분기 `spot_image_url` 실측 | | | U-3 |
| 브라우저 실제 렌더링 | | | U-4 |
| 프록시 502 경로 | | | U-5 |

**FAIL 0건.** 아래 O-1 ~ O-3은 실패가 아니라 기록해 둘 관찰 사항이다.

---

## 1. 화이트리스트 — 코드와 계약서 일치 확인

`livespot_backend/app/api/images.py:40-47` 실제 코드:

```python
_ALLOWED_HOST_SUFFIXES = (".visitkorea.or.kr", ".knto.or.kr")
_ALLOWED_HOSTS = {"visitkorea.or.kr", "tong.visitkorea.or.kr"}
```

`02_backend_contract.md:232-236`의 표(정확 일치 2 + 접미사 2 + 스킴 http/https)와 **문자 단위로 일치**. 접미사에 선행 점이 붙어 있고(`images.py:64` `host.endswith(suffix)`), 스킴 검사가 fetch보다 먼저다(`images.py:57`).

**앱이 감싸는 원본 URL의 실제 호스트 집계** (`/api/live/hotspots` 5건 + `/api/spots/all` 150건, 총 155개 `image_url`/`spot_image_url`):

```
{'tong.visitkorea.or.kr': 155}
```

단일 호스트이고 `_ALLOWED_HOSTS`에 정확 일치로 들어 있다. 대소문자 변형(`TONG.VisitKorea.or.KR`)도 `images.py:59`의 `.lower()` 덕에 **200**으로 통과함을 실측했다.

## 2. 인코딩 · 헤더 실측

앱이 생성하는 것과 동일한 URL:

```
http://127.0.0.1:8000/api/images/proxy?url=http%3A%2F%2Ftong.visitkorea.or.kr%2Fcms%2Fresource%2F02%2F3540002_image2_1.jpg
```

| 요청 | 결과 |
|---|---|
| `Origin` 없음 | 200 / `image/jpg` / 144812 B / `Cache-Control: public, max-age=86400` / **ACAO 없음** |
| `Origin: http://localhost:8080` | 200 / `image/jpg` / **`Access-Control-Allow-Origin: *`** / 144812 B |
| `Origin: http://localhost:53000` | 200 / **ACAO `*`** / 144812 B |
| 같은 URL의 `https://` 변형 | 200 / `image/jpg` / 144812 B |
| 원본에 쿼리스트링+프래그먼트(`?a=1&b=2#frag`) | 200 / `image/jpg` / 144812 B — `03_flutter_wiring.md` 확인 요청 3번 해소 |

→ `03_flutter_wiring.md`의 확인 요청 1·2·3 모두 **통과**: 파라미터 이름은 `url`, 경로는 `/api/images/proxy`, `Uri.encodeComponent` 전체 인코딩이 FastAPI `Query`에서 온전히 복원된다.

**주의(정보)**: ACAO는 `Origin` 헤더가 있을 때만 붙는다. Starlette `CORSMiddleware`의 정상 동작이며 브라우저는 항상 `Origin`을 보내므로 실사용에 문제 없다. `02_backend_contract.md:258`의 실측도 `-H "Origin:"`를 붙인 것이었다 — Origin 없이 curl하면 헤더가 안 보이니 후속 검증자가 오판하지 않도록 계약서에 한 줄 덧붙이면 좋다.

## 3. SSRF 방지 — 전부 400, 모두 0.00초 (fetch 미발생)

| 입력 `url` | 결과 | 소요 |
|---|---|---|
| `http://127.0.0.1:8000/health` | 400 `허용되지 않은 이미지 호스트입니다.` | 0.00s |
| `file:///etc/passwd` | 400 | 0.00s |
| `http://evilvisitkorea.or.kr/x.jpg` | 400 | 0.00s |
| `http://169.254.169.254/latest/meta-data/` (클라우드 메타데이터) | 400 | 0.00s |
| `http://tong.visitkorea.or.kr.attacker.com/x.jpg` (접미사 위조) | 400 | 0.00s |
| `not a url` | 400 | 0.00s |
| `//tong.visitkorea.or.kr/x.jpg` (스킴 없음) | 400 | 0.00s |

정상 이미지 호출이 0.14s인 것과 대비해 차단 케이스는 전부 **0.00s** — 네트워크 왕복이 전혀 없다. 즉 판정이 fetch보다 앞서 일어난다는 것이 시간으로도 증명된다. 계약서에 없던 메타데이터 주소·접미사 위조 2종도 추가로 막힌다.

## 4. `HotspotEntry` 키 대조

`GET /api/live/hotspots` 실측 키(5건 전부 동일):

```
['basis', 'congestion_rate', 'content_id', 'display_level', 'last_report_at', 'report_count', 'spot_address', 'spot_image_url', 'spot_title']
```

`livespot_app/lib/models/hotspot_entry.dart:33-41`이 읽는 키:

```
content_id / spot_title / spot_address / spot_image_url / basis / display_level / report_count / last_report_at / congestion_rate
```

**9 대 9 완전 일치. MISSING 0, UNREAD 0.**

- `spot_title`(이 스키마만 `spot_name`이 아니라 `spot_title`) — 실측 응답에 `spot_title`로 존재하고 Dart도 `json['spot_title'] as String`으로 읽는다. **`03_flutter_wiring.md` 확인 요청 4번 해소**: 키가 실제로 있으므로 "조용히 null로 떨어지는" 시나리오는 발생하지 않는다.
- nullable 정합: 서버 `Optional[str]`(`schemas.py:246`) ↔ Dart `as String?`(`hotspot_entry.dart:36`). 캐스트 예외 없음.
- 5건 전부 `basis="CONGESTION"`이고 `spot_image_url`이 non-null로 채워졌다 → `get_all_seoul_spots()` 분기(`live.py:156`)는 실측됨. `basis="REPORT"` 분기(`live.py:115`)는 현재 DB에 라이브 제보가 없어 **실측 못 함(U-3 참조)**.
- `last_report_at`은 이번 5건 모두 null이라 UTC 보정 경로는 이번 회차에 태우지 못했으나, `_parseUtc`(`hotspot_entry.dart:45-48`)는 기존 검증분과 동일 코드로 변경 없음.

## 5. 상세 이동 시 이미지 전달 — 원본이 넘어간다 (핵심)

`livespot_app/lib/screens/live/live_screen.dart:389-394`:

```dart
spot: Spot(
  contentId: spot.contentId,
  title: spot.spotTitle,
  address: spot.spotAddress,
  imageUrl: spot.spotImageUrl,   // <- 프록시로 감싸지 않은 원본
),
```

`spot.spotImageUrl`은 `HotspotEntry.spotImageUrl`, 즉 서버가 준 **원본 TourAPI URL 그대로**다. 프록시 래핑은 렌더링 시점에만 일어난다:

- `live_screen.dart:431` `final imageUrl = resolveImageUrl(spot.spotImageUrl);` (목록 썸네일)
- `spot_detail_screen.dart:387-388` `resolveImageUrl(widget.spot.imageUrl)` (상세 헤더)
- `briefing_card.dart:84-86` / `bookmarks_screen.dart:164` (나머지 2곳)

`lib/` 전체의 `Image.network` 호출 4곳이 **전부** `resolveImageUrl`을 거친다(grep 확인). 원본을 직접 넘기는 곳은 없다. 요구대로 **`Spot.imageUrl`에는 원본이 저장되고, 감싸기는 화면마다 한 번씩만** 일어난다.

이중 래핑 방지도 확인: `image_url.dart:15`의 `rawUrl.startsWith(_proxyPrefix)` 가드가 쓰는 접두사는 `http://127.0.0.1:8000/api/images/proxy?url=`이고, 실제 생성 URL이 이 접두사로 시작함을 실측했다(→ 두 번 감싸도 그대로 반환).

부수 확인: `bookmarks_screen.dart:50-55`도 `imageUrl: b.spotImageUrl`을 넘긴다. `03_flutter_wiring.md:60`은 "좌표 없이 `Spot(contentId:, title:, address:)`"라고 적었는데 **현재 코드는 `imageUrl`까지 넘긴다** — 코드가 문서보다 앞서 있다(코드 쪽이 옳다). 문서 한 줄 갱신 권고.

## 6. 빈 문자열 정규화 — 어느 쪽이 실제로 동작하는가

**두 층 모두 존재하며, 경로에 따라 실제로 일하는 층이 다르다.**

| 응답 경로 | 서버 정규화 | 앱 정규화 |
|---|---|---|
| `GET /api/live/hotspots` | O `live.py:115,156` `_clean()` | O `resolveImageUrl` |
| `GET /api/bookmarks` | O `spot_lookup.py:76` `_clean()` | O (`bookmarks_screen.dart:161`의 `url.isEmpty` + `resolveImageUrl`) |
| `GET /api/spots/all`, `GET /api/spots/{id}` | **X 없음** — `spots.py:53,65` `image_url=item.get("firstimage", None)` (빈 문자열이 그대로 통과) | O **여기서만 앱이 유일한 방어선** |

즉 **관찰 O-1**: 이번에 추가된 두 경로는 서버가 정규화하지만, `Spot.imageUrl`의 주 공급원인 `/api/spots/*`는 정규화하지 않는다. 이 경로를 실제로 막고 있는 것은 앱의 `resolveImageUrl`이 `rawUrl.isEmpty`를 null로 접는 것(`image_url.dart:13`)과, 그에 맞춰 조건을 `spot.imageUrl != null` → `resolveImageUrl(spot.imageUrl) != null`로 바꾼 `spot_detail_screen.dart:387` / `briefing_card.dart:84` 변경이다. **이 변경이 없었다면 `imageUrl == ''`에서 `!` 단언이 터졌다** — 03 문서의 판단이 맞다.

실측: 현재 `/api/spots/all` 150건 중 `image_url == ""` 0건, `null` 0건(전부 채워짐). 지금은 재현되지 않지만 TourAPI 응답 구성에 따라 언제든 나올 수 있는 값이므로 앱 측 가드는 유지해야 한다. 서버 `spots.py`에도 `_clean()`을 적용하면 세 경로가 같은 규약이 되지만, **이번 작업 범위 밖이며 앱만으로 이미 안전하다** — 선택 사항으로 남긴다(수정 대상: backend-builder, 우선순위 낮음).

## 7. `flutter analyze` 독립 재실행

```
72 issues found. (ran in 3.5s)
```

`03_flutter_wiring.md`가 보고한 72건과 **일치**. 이번 작업으로 추가된 이슈 **0건**:

- `lib/utils/image_url.dart`, `lib/models/hotspot_entry.dart` — 출력에 **한 줄도 등장하지 않음**
- `live_screen.dart`의 신규 `_hotspotLeading`(424-472행) 구간에서 나온 이슈 없음 (`withValues` 사용 확인)
- 잔존 72건은 전부 범위 밖: `firebase_auth` 미설치 error 1, `widget_test.dart::MyApp` error 1, 미사용 import warning 2, 나머지는 `withOpacity`/`background` deprecation info

## 8. 실제 이미지 바이트 — 최종 증거

앱이 만드는 것과 동일한 URL을 그대로 호출한 결과:

```
200  Content-Type: image/jpg  Content-Length: 144812  실수신 바이트: 144812
첫 4바이트: ff d8 ff e0   <- JPEG SOI 매직넘버
Access-Control-Allow-Origin: *   (Origin 헤더 동반 시)
Cache-Control: public, max-age=86400
```

`Content-Length` 헤더와 실수신 바이트 수가 일치하므로 스트리밍 중계에 잘림이 없다.

**근본 원인 재확인**: 원본 CDN을 직접 조회한 응답 헤더는

```
Date / Connection / ETag / Last-Modified / Accept-Ranges / Content-Length / Content-Type
```

— `Access-Control-Allow-Origin`이 **없다**. 프록시가 필요했던 이유(브라우저 차단)가 실측으로 확증됐다. 동시에 `Content-Encoding`도 없으므로, 프록시가 원본 `Content-Length`를 그대로 전달하는 방식(`images.py:110-112`)이 안전하다.

---

## 관찰 사항 (실패 아님)

### O-1. `/api/spots/*`의 `image_url` 빈 문자열 미정규화 — [심각도: 낮음]
위 6절 참조. 앱이 단독으로 막고 있다. 서버 정합을 맞추려면 `livespot_backend/app/api/spots.py:53,65`에 `_clean()` 적용. 수정 대상 `backend-builder`, 선택 사항.

### O-2. 상세 헤더가 `_spotDetail['image_url']`로 폴백하지 않는다 — [심각도: 낮음]
- 위치: `livespot_app/lib/screens/detail/spot_detail_screen.dart:387`
- 헤더 이미지는 오직 `widget.spot.imageUrl`만 본다. `_fetchSpotDetail`(79행)이 받아 온 `_spotDetail['image_url']`은 사용하지 않는다.
- 현재 상세페이지로 들어오는 두 경로(`live_screen.dart:393`, `bookmarks_screen.dart:54`)가 모두 `imageUrl`을 넘기므로 **지금은 증상이 없다.** 다만 앞으로 `imageUrl` 없이 `Spot`을 만드는 진입점이 새로 생기면 이번 버그가 그대로 재발한다.
- 권고(선택): `resolveImageUrl(widget.spot.imageUrl ?? _spotDetail?['image_url'] as String?)`로 폴백을 두면 진입 경로와 무관하게 헤더가 채워진다. 수정 대상 `flutter-builder`.

### O-3. 문서 갱신 2건
- `03_flutter_wiring.md:60` — "좌표 없이 `Spot(contentId:, title:, address:)`"는 현재 코드(`imageUrl` 포함)와 다르다. 코드가 옳다.
- `02_backend_contract.md` 프록시 절 — ACAO는 `Origin` 헤더가 있을 때만 붙는다는 점을 한 줄 명시 권고(Origin 없이 curl하면 헤더가 안 보여 오판하기 쉽다).

---

## 미검증 항목과 이유

- **U-3. `basis="REPORT"` 분기의 `spot_image_url`(`live.py:115`)** — 현재 DB에 LIVE 윈도 내 제보가 없어 실측 5건이 전부 `CONGESTION`이다. 코드상 두 분기가 같은 `_clean()` 헬퍼를 쓰고 스키마도 동일하지만, **REPORT 경로의 실제 JSON은 이번 회차에 보지 못했다.** 제보가 한 건이라도 쌓인 뒤 재검증 필요.
- **U-4. 브라우저 실제 렌더링** — `flutter run`은 하지 않는다(사용자 구동 항목). 프록시가 ACAO `*`와 정상 JPEG 바이트를 준다는 것까지가 서버 측에서 증명 가능한 전부다. 화면에 실제로 그려지는지는 사용자 확인.
- **U-5. 프록시 502 경로(타임아웃/5xx/비이미지 응답)** — 화이트리스트 호스트가 실제로 타임아웃하거나 HTML을 반환하는 상황을 인위적으로 만들 수 없어 미실측. 404 경로는 `02_backend_contract.md:275`에 backend-builder 실측이 있고, 앱은 어떤 실패든 `errorBuilder` 폴백이므로 동작 영향 없음.

## 실행 검증 결과

- 서버 기동: 성공 (`GET /health` → `{"status":"ok"}`)
- `GET /api/live/hotspots` → 5건, 최상위 키 9개: `['basis','congestion_rate','content_id','display_level','last_report_at','report_count','spot_address','spot_image_url','spot_title']`
- `GET /api/spots/all` → 150건, 키 8개(`address, content_id, content_type_id, dist, image_url, mapx, mapy, title`), `image_url` 빈 문자열 0건
- `GET /api/spots/{id}` → 키 11개, `image_url` non-null 확인
- `GET /api/images/proxy` → 정상 200 4종(http / https / 대소문자 호스트 / 쿼리스트링 포함), 차단 400 7종(전부 0.00s)
- `flutter analyze` → **72 issues** (baseline 72, 신규 0)
