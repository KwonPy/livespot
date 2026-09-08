# 백엔드 계약서: 북마크 API

> 대상: `01_spec.md` 2절 B(P-B1~P-B23). 아래 응답 예시는 전부 **실제 서버 curl 실측 원문**이다(추정·수기 작성 아님).
> `flutter-builder`는 이 문서의 필드명·타입·nullable을 그대로 베낀다.
> 검증 환경: `uvicorn app.main:app --port 8000`, `TEST_MODE=true`, DB `livespot.db` (마이그레이션 `263b3684e281` 적용 후).

## 공통 규약

- 모든 응답 필드는 **snake_case**. `alias_generator` 없음 — Pydantic 필드명이 그대로 JSON 키다.
- `created_at`은 **naive UTC**(타임존 표기 없음). 예: `"2026-09-08T09:39:18.528924"`. Dart는 파싱 시 `Z`를 붙여야 한다.
- 3개 엔드포인트 모두 `Depends(get_current_user_id)`. 평소 `test_user`, `TEST_MODE`에서만 `X-Test-User-Id` 헤더로 전환. **앱은 기존 인터셉터가 헤더를 붙이므로 추가 작업 없음**(P-B2).
- GPS 인증 없음(P-B12) · Credit 지급 없음(P-B13) · 만료 없음(P-B14).
- **단건 상태 조회 엔드포인트는 없다**(P-B11). 상세페이지는 `GET /api/bookmarks`를 받아 `content_id` 포함 여부로 판정한다.

---

### POST /api/bookmarks

북마크 추가. **멱등** — 이미 북마크된 상태로 다시 호출해도 409가 아니라 200(P-B7).

- 요청: `BookmarkCreate`
  - `content_id` : string : required — TourAPI content_id 원문 문자열
- 응답: `BookmarkToggleResponse`
  - `content_id`  : string  : non-null
  - `bookmarked`  : bool    : non-null (항상 `true`)

- 실제 응답 예시 (최초 추가):
  ```
  curl -s -X POST http://127.0.0.1:8000/api/bookmarks \
    -H "Content-Type: application/json" -d '{"content_id":"126508"}'
  ```
  ```json
  {"content_id":"126508","bookmarked":true}
  ```

- 실제 응답 예시 (**같은 content_id 두 번째 POST — 멱등성 실측**):
  ```
  HTTP 200
  {"content_id":"126508","bookmarked":true}
  ```
  DB 확인 결과 행은 **1개**로 유지된다:
  ```
  ('00000000-0000-0000-0000-000000000001', '126508', 1)
  total rows: 2
  ```

- 에러:
  - `422` — body에 `content_id`가 없거나 문자열이 아닐 때 (FastAPI 기본 검증)
  - **409·404는 발생하지 않는다.** 중복 추가는 정상 200이다.

---

### DELETE /api/bookmarks/{content_id}

북마크 해제. **멱등** — 북마크가 없어도 404가 아니라 200(P-B8).

- 요청: path parameter `content_id` (string). body 없음.
- 응답: `BookmarkToggleResponse`
  - `content_id`  : string  : non-null
  - `bookmarked`  : bool    : non-null (항상 `false`)

- 실제 응답 예시 (존재하는 북마크 해제):
  ```
  curl -s -X DELETE http://127.0.0.1:8000/api/bookmarks/264337
  ```
  ```json
  {"content_id":"264337","bookmarked":false}
  ```
  HTTP 200

- 실제 응답 예시 (**이미 해제된 것 재삭제 — 멱등성 실측**):
  ```json
  {"content_id":"264337","bookmarked":false}
  ```
  HTTP 200

- 실제 응답 예시 (**한 번도 북마크한 적 없는 id**):
  ```json
  {"content_id":"999999999","bookmarked":false}
  ```
  HTTP 200

- 에러: 없음. 어떤 `content_id`를 넘겨도 200이다(해제의 목적은 "없는 상태"이고 그건 이미 달성됐다).

---

### GET /api/bookmarks

내 북마크 목록. 정렬 `created_at DESC`(최신이 위, P-B15). 0건이면 **빈 배열**(P-B9).

- 요청: 없음(쿼리 파라미터·페이지네이션 없음)
- 응답: `List[BookmarkEntry]`

| 필드 | 타입 | nullable | 비고 |
|---|---|---|---|
| `content_id` | string | **non-null** | `spot_content_id`가 **아니다**. `MyReportEntry`와 키 이름이 다르니 주의 |
| `spot_name` | string | **nullable** | TourAPI 조인 결과. 실패 시 null |
| `spot_address` | string | **nullable** | TourAPI `addr1` |
| `spot_image_url` | string | **nullable** | TourAPI `firstimage`. 빈 문자열은 null로 정규화됨 |
| `created_at` | datetime | **non-null** | naive UTC ISO8601 |

중첩 객체 없음 — 평평한 오브젝트의 배열이다.

- 실제 응답 예시 (**0건 — 에러가 아니라 빈 배열**):
  ```json
  []
  ```

- 실제 응답 예시 (2건, 최신순):
  ```json
  [
      {
          "content_id": "132215",
          "spot_name": "가락농수산물종합도매시장",
          "spot_address": "서울특별시 송파구 양재대로 932 (가락동)",
          "spot_image_url": "http://tong.visitkorea.or.kr/cms/resource/37/3568037_image2_1.jpg",
          "created_at": "2026-09-08T09:39:39.961484"
      },
      {
          "content_id": "126508",
          "spot_name": "경복궁",
          "spot_address": "서울특별시 종로구 사직로 161 (세종로)",
          "spot_image_url": "https://tong.visitkorea.or.kr/cms/resource/98/3487598_image2_1.jpg",
          "created_at": "2026-09-08T09:39:18.528924"
      }
  ]
  ```

- 실제 응답 예시 (**TourAPI 조인 실패 항목 — P-B18 폴백 경로**):
  존재하지 않는 관광지 `264337`을 북마크했을 때. 항목이 목록에서 **빠지지 않고** `spot_*` 3개가 null로 온다:
  ```json
  {"content_id":"264337","spot_name":null,"spot_address":null,"spot_image_url":null,"created_at":"2026-09-08T09:39:18.613252"}
  ```
  → 앱은 `'관광지 정보 없음 (ID 264337)'` 폴백으로 그리고, **탭 이동은 그대로 허용**한다(상세페이지가 자체 재조회).
  이미지가 null일 때의 플레이스홀더도 필요하다.

- 실측 키 목록 (Dart `fromJson` 대조용):
  ```
  ['content_id', 'created_at', 'spot_address', 'spot_image_url', 'spot_name']
  ```

- 에러: 없음. 빈 상태에 404를 내지 않는다.

---

## 사용자 격리 실측 (검증 포인트 4)

`X-Test-User-Id`를 바꾸면 목록이 실제로 갈라진다:

```
seed_user_01 초기 목록        → []
seed_user_01이 126508 북마크  → {"content_id":"126508","bookmarked":true}
seed_user_01 목록             → 1건: ['126508']
기본 사용자 목록              → 2건: ['132215', '126508']   (영향 없음)
seed_user_01이 126508 해제 후 → 기본 사용자 여전히 2건
```

동일 `content_id`를 서로 다른 사용자가 북마크하는 것은 정상이다 — UNIQUE는 `(user_id, spot_content_id)` 조합이다.

## DB 제약 실측

라우터 조건문이 아니라 **DB 제약이 최종 방어선**(P-B4). 직접 중복 INSERT를 시도하면:

```
UNIQUE constraint failed: bookmarks.user_id, bookmarks.spot_content_id
```

---

## 구현된 파일

| 파일 | 상태 |
|---|---|
| `livespot_backend/app/models/schemas.py` | 수정 — `BookmarkCreate`, `BookmarkToggleResponse`, `BookmarkEntry` 추가(파일 끝) |
| `livespot_backend/app/db/models/bookmark.py` | 신규 — `Bookmark` 모델 |
| `livespot_backend/app/db/models/__init__.py` | 수정 — `Bookmark` import 등록 |
| `livespot_backend/app/api/bookmarks.py` | 신규 — 라우터 3개 |
| `livespot_backend/app/api/router.py` | 수정 — `include_router(bookmarks.router, prefix="/bookmarks", tags=["bookmarks"])` |
| `livespot_backend/app/services/spot_lookup.py` | 수정 — `resolve_spot_cards()` **추가**. 기존 `resolve_spot_names()`는 한 글자도 건드리지 않음 |
| `livespot_backend/migrations/versions/263b3684e281_add_bookmarks_table.py` | 신규 — `down_revision='12e638fbc565'`, `upgrade head` 적용 완료 |

**건드리지 않음**(명세 6절 준수): `services/credit.py`, `api/credits.py`, `api/reports.py`, `api/questions.py`.

### `bookmarks` 테이블

```
id              String(36) PK   default uuid4
user_id         String(36)      FK users.id, index, not null
spot_content_id String(20)      index, not null
created_at      DateTime        index, not null, default utcnow
UNIQUE(user_id, spot_content_id) name='uq_bookmark_user_spot'
```

---

## flutter-builder를 위한 주의사항

1. **엔트리 키는 `content_id`이지 `spot_content_id`가 아니다.** `MyReportEntry`(`spot_content_id`)를 복사해 오면 여기서 null이 난다. `spot_` 접두사는 조인된 3개 필드에만 붙는다.
2. `spot_name` / `spot_address` / `spot_image_url` 3개는 **전부 nullable**이다. non-null 캐스팅하면 삭제된 관광지에서 예외가 난다.
3. `created_at`은 naive UTC다. 기존 `HotspotEntry._parseUtc` 패턴을 그대로 쓴다.
4. POST·DELETE는 실패해도 2xx가 아닌 응답이 사실상 없으므로, 토글 롤백은 네트워크 예외 기준으로만 하면 된다.
5. 상세페이지 북마크 상태는 `GET /api/bookmarks`의 `content_id` 포함 여부로 판정한다 — 단건 조회 API를 찾지 마라.

---

# 백엔드 계약서 (추가분): 이미지 CORS 프록시 + HOT SPOTS 대표이미지

> 검증 환경: `venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8000 --host 127.0.0.1`.
> 아래 응답·상태코드는 전부 **실제 curl 실측 원문**이다.

## 배경 (왜 프록시가 필요한가)

`image_url`(TourAPI `firstimage`)은 서버가 원래부터 정상적으로 내려주고 있었다. 문제는 그 이미지가 올라가 있는 `tong.visitkorea.or.kr`이 **`Access-Control-Allow-Origin` 헤더를 전혀 보내지 않는다**는 점이다. Flutter Web(CanvasKit/Skwasm)의 `Image.network`는 이미지 바이트를 fetch로 받아오므로, CORS 헤더가 없으면 브라우저가 응답을 차단하고 앱은 조용히 회색 placeholder만 남는다. curl로는 200 OK에 정상 바이트가 오기 때문에 "API 키 문제"로 오인하기 쉬운 증상이었다.

우리 서버는 `app/main.py`에 `CORSMiddleware(allow_origins=["*"])`가 걸려 있으므로, 이미지를 서버가 대신 받아 중계하면 브라우저가 문제없이 읽는다.

---

## GET /api/images/proxy

- **요청**: 쿼리 파라미터 `url` (필수, 문자열) — **URL 인코딩된 원본 이미지 절대 주소**. 요청 본문 없음.
- **응답**: JSON 아님. 원본 이미지 바이트를 그대로 스트리밍한다.
  - `Content-Type`: 원본 응답 그대로 전달 (예: `image/jpg`, `image/jpeg`, `image/png`)
  - `Cache-Control: public, max-age=86400` — 서버는 캐시하지 않는다(설계 원칙 2). 반복 요청은 브라우저 HTTP 캐시가 흡수한다.
  - `Access-Control-Allow-Origin: *` (CORSMiddleware가 부여 — 이 엔드포인트의 존재 이유)
  - `Content-Length`: 원본에 있으면 그대로 전달

### 화이트리스트 (SSRF 방지)

`url`의 호스트가 아래에 해당하지 않으면 **fetch조차 하지 않고 400**을 반환한다.

| 규칙 | 값 |
|---|---|
| 정확히 일치 | `visitkorea.or.kr`, `tong.visitkorea.or.kr` |
| 도메인 접미사 | `.visitkorea.or.kr`, `.knto.or.kr` |
| 스킴 | `http`, `https` 만 허용 |

접미사는 반드시 **앞에 점을 붙여** 비교한다 — `evilvisitkorea.or.kr` 같은 유사 호스트가 통과하면 화이트리스트가 무의미해진다(실측으로 차단 확인).

실제 응답에 등장하는 호스트는 `tong.visitkorea.or.kr` 하나다. 목록 API(`/api/spots/all`)는 `http://`, 상세 API(`/api/spots/{id}`)는 `https://`로 같은 호스트를 준다 — 둘 다 통과한다.

### 에러

| 코드 | 언제 |
|---|---|
| 400 | 화이트리스트 밖 호스트, `http`/`https`가 아닌 스킴, 호스트를 파싱할 수 없는 문자열. **원본을 fetch하지 않는다** |
| 404 | 원본이 4xx로 응답 (삭제된 이미지 등) |
| 502 | 원본이 5xx / 타임아웃(총 5초, connect 3초) / DNS·연결 실패 / 이미지가 아닌 응답(`Content-Type`이 `image/`로 시작하지 않음) |
| 422 | `url` 파라미터 누락 (FastAPI 기본) |

### 실측 (curl 원문)

```
$ curl -s -o /dev/null -w "%{http_code} %{content_type} %{size_download}\n" \
    "http://127.0.0.1:8000/api/images/proxy?url=http%3A%2F%2Ftong.visitkorea.or.kr%2Fcms%2Fresource%2F90%2F3467490_image2_1.jpg"
200 image/jpg 185308

$ curl -s -o /dev/null -D - -H "Origin: http://localhost:8080" "http://127.0.0.1:8000/api/images/proxy?url=<위와 동일>"
cache-control: public, max-age=86400
content-type: image/jpg
access-control-allow-origin: *

$ curl -s -w " | %{http_code}\n" "http://127.0.0.1:8000/api/images/proxy?url=http%3A%2F%2Fexample.com%2Fx.jpg"
{"detail":"허용되지 않은 이미지 호스트입니다."} | 400

$ curl -s -w " | %{http_code}\n" "http://127.0.0.1:8000/api/images/proxy?url=http%3A%2F%2F127.0.0.1%3A8000%2Fhealth"
{"detail":"허용되지 않은 이미지 호스트입니다."} | 400

$ curl -s -w " | %{http_code}\n" "http://127.0.0.1:8000/api/images/proxy?url=http%3A%2F%2Fevilvisitkorea.or.kr%2Fx.jpg"
{"detail":"허용되지 않은 이미지 호스트입니다."} | 400

$ curl -s -w " | %{http_code}\n" "http://127.0.0.1:8000/api/images/proxy?url=file%3A%2F%2F%2Fetc%2Fpasswd"
{"detail":"허용되지 않은 이미지 호스트입니다."} | 400

$ curl -s -w " | %{http_code}\n" "http://127.0.0.1:8000/api/images/proxy?url=http%3A%2F%2Ftong.visitkorea.or.kr%2Fcms%2Fresource%2F00%2Fnope_does_not_exist.jpg"
{"detail":"원본 이미지를 찾을 수 없습니다."} | 404
```

### 앱 사용법 (flutter-builder)

서버가 내려주는 `image_url` / `spot_image_url`은 **항상 원본 TourAPI URL**이다. 프록시로 감싸는 것은 앱의 몫이다.

```dart
String proxied(String raw) =>
    '${ApiService.baseUrl}/images/proxy?url=${Uri.encodeComponent(raw)}';
```

- `Uri.encodeComponent`를 반드시 쓴다(`encodeFull` 아님) — `://`와 `/`가 인코딩돼야 쿼리 값으로 온전히 전달된다.
- 이미 프록시로 감싼 URL을 두 번 감싸지 않도록 주의한다.
- null 체크는 그대로 유지한다. 감싸기 전에 `raw`가 null/빈 문자열이면 프록시를 호출하지 말고 placeholder를 그린다.

---

## GET /api/live/hotspots (변경)

`HotspotEntry`에 **`spot_image_url` 한 필드만 추가**했다. 기존 필드는 이름·타입·순서 모두 그대로다.

- **요청**: 쿼리 `limit` (int, 기본 5)
- **응답**: `List[HotspotEntry]`

| 필드 | 타입 | nullable | 비고 |
|---|---|---|---|
| `content_id` | string | X | TourAPI content_id (`spot_content_id` 아님) |
| `spot_title` | string | X | (`spot_name` 아님 — 이 스키마만 `spot_title`이다) |
| `spot_address` | string | O | TourAPI `addr1` |
| **`spot_image_url`** | **string** | **O** | **신규.** TourAPI `firstimage` **원본 URL 그대로**. 빈 문자열은 서버가 null로 정규화한다. 조회 실패·이미지 없음이면 null이며, **그래도 항목은 목록에서 빠지지 않는다** |
| `basis` | string | X | `"REPORT"` \| `"CONGESTION"` |
| `display_level` | string | X | `"EASY"` \| `"NORMAL"` \| `"BUSY"` |
| `report_count` | int | O | `basis="REPORT"`일 때만 |
| `last_report_at` | datetime | O | `basis="REPORT"`일 때만. **naive UTC** — Dart는 `Z`를 붙여 파싱 |
| `congestion_rate` | float | O | `basis="CONGESTION"`일 때만 |

`spot_image_url`은 두 분기 모두에서 채운다: `basis="REPORT"`는 `tour_service.get_spot_detail()`의 `firstimage`, `basis="CONGESTION"`은 `get_all_seoul_spots()` 목록 항목의 `firstimage`. 별도 API 호출이 늘지 않는다 — 이미 이름·주소를 뽑던 같은 응답에서 한 키를 더 읽을 뿐이다.

### 실측 (curl 원문)

```
$ curl -s "http://127.0.0.1:8000/api/live/hotspots"
```
```json
[
  {
    "content_id": "130938",
    "spot_title": "광나루안전체험관",
    "spot_address": "서울특별시 광진구 능동로 238",
    "spot_image_url": "http://tong.visitkorea.or.kr/cms/resource/02/3540002_image2_1.jpg",
    "basis": "CONGESTION",
    "display_level": "BUSY",
    "report_count": null,
    "last_report_at": null,
    "congestion_rate": 93.54
  },
  {
    "content_id": "1604784",
    "spot_title": "경희궁 흥화문",
    "spot_address": "서울특별시 종로구 새문안로 55 (신문로2가)",
    "spot_image_url": "http://tong.visitkorea.or.kr/cms/resource/55/3384855_image2_1.JPG",
    "basis": "CONGESTION",
    "display_level": "BUSY",
    "report_count": null,
    "last_report_at": null,
    "congestion_rate": 85.31
  }
]
```

키 목록 실측: `['basis', 'congestion_rate', 'content_id', 'display_level', 'last_report_at', 'report_count', 'spot_address', 'spot_image_url', 'spot_title']`

- **에러**: 없음. TourAPI가 실패하면 빈 배열 또는 해당 항목만 빠진다(기존 폴백 규약 유지).

---

## 변경 파일

| 파일 | 변경 |
|---|---|
| `livespot_backend/app/api/images.py` | **신규** — 프록시 라우터. 화이트리스트 판정 `_is_allowed()`, `get_session()` 재사용, `StreamingResponse` 중계 |
| `livespot_backend/app/api/router.py` | 수정 — `include_router(images.router, prefix="/images", tags=["images"])` |
| `livespot_backend/app/models/schemas.py` | 수정 — `HotspotEntry.spot_image_url: Optional[str] = None` 추가 |
| `livespot_backend/app/api/live.py` | 수정 — 두 분기에서 `spot_image_url` 채움, 빈 문자열 정규화 헬퍼 `_clean()` 추가 |

DB 변경 없음 → **마이그레이션 없음**. 이미지를 DB·디스크에 저장하지 않는다(설계 원칙 2).
