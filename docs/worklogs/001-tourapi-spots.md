# 관광지 데이터 기반 (TourAPI 실시간 연동 + 지도)

> 소급 기록 — 2026-09-01 작성. 실제 구현은 그 이전에 완료됐고, 현재 코드 상태를 기준으로 정리했다.

## 1. 한 줄 요약

한국관광공사 TourAPI를 실시간으로 호출해 관광지 목록·상세·주변·사진을 가져오고, 지도에 마커로 뿌리는 기반 계층.

## 2. 왜 만들었는가

LiveSpot의 모든 기능은 "어떤 관광지에 대한 것인지"가 있어야 성립한다. 제보도, Q&A도, 혼잡도도 전부 관광지 하나에 붙는 정보다. 그래서 관광지 데이터를 가져오는 층이 가장 먼저 필요했다.

관광지 정보 자체는 우리가 만드는 데이터가 아니라 공공데이터다. 공모전 주최 측이 **데이터를 우리 DB에 복사해두지 말고 매번 API를 호출해서 쓰라고 권고**했기 때문에, 로컬에 `spots` 테이블을 두지 않는 방향으로 설계했다.

## 3. 구현한 것

- TourAPI(KorService2) 연동 서비스 — 목록/상세/소개정보/키워드검색/주변검색
- 관광사진 갤러리 API(PhotoGalleryService1) 연동
- 관광지 관련 엔드포인트 8개
- Flutter 지도 화면 — MapTiler 지도 위에 관광지 마커, 마커를 누르면 카드가 뜨고 상세로 연결
- 탐색/검색 화면

## 4. 동작 흐름

```
Flutter 지도 화면
→ ApiService.fetchNearbySpots(위도, 경도)
→ POST /api/spots/nearby
→ TourAPIService (aiohttp로 공공데이터 호출)
→ 한국관광공사 TourAPI
→ 응답 JSON에서 item 배열만 추출
→ 지역/카테고리/좌표 필터링
→ SpotBase 리스트로 변환
→ Dart Spot.fromJson
→ 지도 마커
```

DB를 거치지 않는다. 관광지 정보는 요청이 올 때마다 공공데이터에서 새로 받아온다.

## 5. 주요 파일

**백엔드**
- `livespot_backend/app/services/tour_api.py` — TourAPI 호출 담당. 재시도, 캐시, 응답 파싱
- `livespot_backend/app/services/photo_gallery.py` — 관광사진 갤러리 API
- `livespot_backend/app/services/http_client.py` — aiohttp 세션을 하나만 만들어 재사용
- `livespot_backend/app/services/cache.py` — 의존성 없는 최소 TTL 캐시
- `livespot_backend/app/api/spots.py` — 관광지 엔드포인트 + TourAPI 응답을 우리 스키마로 바꾸는 변환 함수

**프론트**
- `livespot_app/lib/services/api_service.dart` — 서버 호출 전담
- `livespot_app/lib/models/spot.dart` — 서버 JSON을 Dart 객체로 변환
- `livespot_app/lib/screens/map/map_screen.dart` — 지도 화면
- `livespot_app/web/index.html` — MapTiler 지도 JS. Flutter가 여기 함수를 호출한다

## 6. 핵심 코드 / 개념

**TourAPI 응답에서 목록을 꺼내는 부분** (`tour_api.py`의 `_extract_items`)

공공데이터 응답은 `response.body.items.item` 처럼 깊게 감싸여 있고, 결과가 없으면 `items`가 빈 문자열 `""`로 오고, 결과가 1건이면 배열이 아니라 객체 하나로 온다. 이 세 경우를 매번 따로 처리하면 코드가 더러워지므로 한 함수에 모아뒀다.

```python
items = body.get("items", {})
if isinstance(items, str) and items == "":   # 결과 0건
    return []
item_list = items.get("item", [])
if isinstance(item_list, dict):              # 결과 1건
    return [item_list]
return item_list if item_list else []
```

**화이트리스트 필터** (`spots.py`의 `_filter_allowed_items`)

TourAPI는 음식점·숙박도 같이 준다. 우리는 관광지·문화시설·축제·레포츠·쇼핑(12/14/15/28/38)만 쓰고, 좌표가 없는 항목은 지도에 못 찍으니 제외한다.

**MapTiler를 Flutter 웹에서 쓰는 방법**

Flutter용 MapTiler 패키지가 없어서, `web/index.html`에 지도 JS를 직접 넣고 Dart에서 `dart:html`·`js` 로 그 JS 함수(`initSpotMap`, `updateSpotMarkers`, `panToSpotMap`)를 호출한다. 반대 방향(마커 클릭 → Dart)은 `js.context['onSpotMarkerClick']`에 Dart 함수를 꽂아두는 식으로 연결했다.

## 7. 사용한 기술

| 기술 | 용도 |
|---|---|
| 한국관광공사 TourAPI (KorService2) | 관광지 목록·상세·소개·검색·주변 |
| PhotoGalleryService1 | 관광 사진 |
| aiohttp | 비동기 HTTP 호출 |
| MapTiler SDK JS | 웹 지도 |
| `dart:html` / `dart:js` | Flutter 웹에서 JS 호출 |
| Dio | Flutter의 HTTP 클라이언트 |

## 8. 문제와 해결

- **문제:** TourAPI가 가끔 429(요청 과다)를 돌려주고, 그때마다 화면이 비었다.
- **원인:** 공공데이터 API의 호출 제한. 특히 여러 콘텐트타입을 병렬로 부를 때 몰린다.
- **해결:** `_fetch`에 429 전용 재시도를 넣었다. 1초 → 2초 → 4초로 점점 길게 기다렸다 다시 부른다(지수 백오프). 다른 오류는 재시도하지 않고 빈 결과를 돌려준다.
- **배운 점:** 외부 API는 "실패할 수 있는 것"으로 다뤄야 한다. 읽기 경로가 실패해도 화면은 살아 있어야 한다는 원칙이 여기서 나왔다.

- **문제:** 같은 관광지 상세를 짧은 시간에 여러 번 호출하게 된다(핫스팟 목록 + 제보 + 상세).
- **원인:** 로컬 캐싱을 하지 않기로 했으니 호출이 중복되는 건 구조상 당연하다.
- **해결:** DB 캐싱이 아닌 **메모리 TTL 캐시**(`cache.py`)를 뒀다. 목록은 5분, 상세는 그보다 길게. "DB에 저장하지 않는다"는 원칙은 지키면서 호출 수만 줄인다.
- **배운 점:** "캐싱 금지" 원칙의 의도는 *데이터가 낡은 채로 남는 것*을 막는 것이지, 모든 캐시를 금지하는 게 아니다. 짧은 TTL 메모리 캐시는 원칙과 충돌하지 않는다.

## 9. 의사결정

### 사용자가 준 정책 (원문)

> 공공데이터는 실시간 호출 방식으로! 우리 앱에서 생성된 실시간 데이터를 제외하고는 map, home화면의 검색탭에서 데이터를 불러올때 모두 api 실시간 호출 방식으로 반영(데이터 동기화 오류방지 위해 공모전 주최측에서 강력히 권고)

### 정책에 없어서 확정한 것

| 쟁점 | 결정 | 근거 |
|---|---|---|
| 관광지 참조를 로컬 FK로 둘까 | **두지 않는다.** `spots` 테이블 없이 TourAPI의 `content_id` 문자열을 그대로 저장 | 로컬 테이블을 만들면 결국 복사본이 생긴다. 제목·주소는 필요할 때 TourAPI를 다시 불러 붙인다 |
| 메모리 캐시도 금지인가 | **허용.** 목록 5분 TTL | 원칙의 목적은 데이터 불일치 방지다. 분 단위 캐시는 불일치를 만들지 않으면서 쿼터를 크게 아낀다 |
| 지도 라이브러리 | MapTiler 유지 (`dart:html` 직접 연동) | 이미 붙어 있고 동작한다. 교체는 모바일 전환 시점의 과제 |

## 10. 배운 것

- 공공데이터 API 응답은 스키마가 들쭉날쭉하다(0건일 때 빈 문자열, 1건일 때 객체). 파싱 함수 하나로 모아두면 나머지 코드가 깨끗해진다.
- Flutter 웹에서 JS 라이브러리를 쓰려면 `index.html`에 JS를 두고 양방향으로 함수를 주고받는 방식이 가장 확실하다.
- 비동기 HTTP 세션은 요청마다 만들지 않고 하나를 재사용해야 한다(`http_client.py`).

## 11. 현재 한계

- `dart:html` 방식은 Flutter가 지원 중단을 예고한 API이고, 모바일 빌드가 안 된다. 웹 전용이다.
- MapTiler API 키가 `web/index.html`에 그대로 들어 있다. 웹 지도 키라 노출 자체는 일반적이지만, 도메인 제한을 걸어두지 않았다.
- `SERVICE_AREA_FILTER` 기본값이 `none`이라 현재는 전국이 나온다. 운영 시 `seoul`로 바꿔야 한다.
- `GET /api/spots/{id}/crowdedness`, `GET /api/spots/{id}/briefing`은 남아 있지만 앱이 쓰지 않는 레거시 경로다.

## 12. 다음 단계

- 이 위에 우리 데이터(제보)를 쌓는다 → [002-report-gps-verification.md](002-report-gps-verification.md)
- 지도 마커 색상에 쓸 혼잡도 판정 → [004-congestion-prediction.md](004-congestion-prediction.md)
