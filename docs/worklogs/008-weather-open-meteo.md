# 관광지 실시간 날씨 (Open-Meteo 연동)

## 1. 한 줄 요약

관광지 상세페이지 헤더에 현재 기온과 날씨 아이콘을 실제 데이터로 보여주게 했다. 기존에 있던 날씨 코드는 파일만 존재하고 어디서도 쓰이지 않는 죽은 코드였다.

## 2. 왜 만들었는가

`function.md`에는 날씨가 독립 기능이 아니라 2장 구조도의 외부 데이터 소스이자, 기능 10(AI 브리핑)의 입력 재료로만 등장한다. `weather.py`는 이미 있었지만 OpenWeatherMap을 부르도록 짜여 있었고, `.env`의 `OPENWEATHER_API_KEY`가 빈 값이라 애초에 동작할 수 없는 상태였다. 그보다 더 근본적으로, 이 파일을 import하는 코드가 프로젝트 어디에도 없어서 "연결된 적 없는" 사문(死文)이었다(`README.md`에도 "코드 존재, 미연결"로 정확히 기록돼 있었다).

기능 10 전체에 착수하기 전에, 먼저 재료 하나(날씨)를 실제로 동작하게 만들고 상세페이지에 보여주는 작업만 떼어서 진행했다.

## 3. 구현한 것

- 백엔드: OpenWeatherMap 호출 코드를 제거하고 Open-Meteo Forecast API를 부르는 `WeatherService`로 전면 교체 (API 키 불필요)
- 백엔드: `GET /api/spots/{content_id}/weather` 단건 조회 엔드포인트 추가
- 백엔드: WMO 날씨 코드(숫자) → 한국어 문구 + 아이콘 키 변환 매핑 10종
- 백엔드: 좌표 기준 5분 메모리 캐시(`TTLCache`)
- 프론트: `WeatherInfo` Dart 모델을 서버 응답 기준으로 재작성 (`fromJson`이 원래 없었다 — 기존 모델은 서버와 한 번도 대조된 적 없는 mock 전용 클래스였다)
- 프론트: 상세페이지 헤더 이미지 위에 기온+아이콘 배지 오버레이 추가 (기존 섹션 순서 무변경)
- 프론트: 지도 화면 브리핑 카드의 "28도 맑음" 하드코딩 배지도 같은 API로 교체

## 4. 동작 흐름

```
상세페이지 진입 (앱은 content_id만 가지고 있음, 좌표는 모를 수 있음)
→ Flutter ApiService.fetchWeather(contentId)
→ FastAPI GET /api/spots/{content_id}/weather
→ 서버가 TourAPI에서 관광지 좌표 조회 (mapy → 위도, mapx → 경도)
→ Open-Meteo Forecast API 호출 (latitude, longitude, current=temperature_2m,weather_code)
→ WMO 코드를 한국어 문구 + 아이콘 키로 변환
→ 좌표 기준 5분 메모리 캐시에 저장
→ {temp, description, humidity, weather_code, icon, available} 응답 (실패해도 200)
→ Dart WeatherInfo.fromJson
→ WeatherBadge 위젯 (헤더 이미지 우측 상단 노란 pill)
```

## 5. 주요 파일

- `livespot_backend/app/services/weather.py` — Open-Meteo 호출, WMO 코드 변환, 5분 캐시
- `livespot_backend/app/models/schemas.py` — `WeatherInfo` 스키마
- `livespot_backend/app/api/spots.py` — `GET /{content_id}/weather` 엔드포인트
- `livespot_app/lib/models/weather.dart` — 서버 응답 → Dart 객체 변환 (`fromJson`)
- `livespot_app/lib/services/api_service.dart` — `fetchWeather(contentId)`
- `livespot_app/lib/widgets/weather_badge.dart` — 배지 위젯, `icon` 키 → 아이콘 매핑
- `livespot_app/lib/screens/detail/spot_detail_screen.dart` — 헤더 오버레이 배치
- `livespot_app/lib/widgets/briefing_card.dart` — 지도 화면 배지 교체

## 6. 핵심 코드 / 개념

**좌표는 앱이 아니라 서버가 구한다**

상세페이지에 들어가는 경로가 두 가지인데, 그중 HOT SPOTS 목록에서 들어가는 경로는 앱이 관광지의 위도·경도를 아예 모르는 상태로 진입한다(`Spot(contentId, title, address)`만 들고 있고 좌표는 null). 앱이 좌표를 서버에 실어 보내는 방식으로 만들었다면 이 경로에서 날씨가 조용히 깨졌을 것이다. 그래서 서버가 `content_id`만 받아 TourAPI로 좌표를 직접 조회한 뒤 Open-Meteo를 부르게 했다. `/congestion` 엔드포인트가 이미 같은 방식을 쓰고 있어서 그 패턴을 그대로 따랐다.

**mapx/mapy 뒤집힘 함정**

TourAPI는 위도를 `mapy`, 경도를 `mapx`라는 필드명으로 준다. 이름이 x/y라서 "x=경도, y=위도"를 깜빡하고 거꾸로 넣기 쉽다. QA 단계에서 실제로 뒤집어 호출해봤는데, 위도 범위(-90~90)를 벗어난 값이 들어가면 Open-Meteo가 400 에러를 내서 `available:false`로 눈에 띄게 실패했다. 즉 "서울 좌표인데 조용히 남태평양 날씨가 나오는" 최악의 시나리오는 한국 좌표에 대해서는 구조적으로 일어나지 않는다는 것까지 확인됐다.

**날씨 코드 해석은 서버만 한다**

Open-Meteo는 날씨 상태를 `weather_code`라는 숫자(WMO 코드)로 준다. 이 숫자를 앱이 직접 보고 "2면 구름 조금이니까 이 아이콘"처럼 판단하게 하면, 나중에 매핑 기준이 바뀔 때 서버·앱 두 곳을 같이 고쳐야 한다. 그래서 서버가 숫자를 한국어 문구(`description`)와 아이콘 키(`icon`) 두 가지로 미리 변환해서 내려주고, 앱은 그 값을 그대로 화면에 옮기기만 한다.

**실패해도 항상 200**

Open-Meteo 호출이 실패해도 서버는 에러를 던지지 않고 `available:false`와 기본값("정보 없음", `icon:"unknown"`)을 채운 객체를 정상 응답(200)으로 돌려준다. 앱은 상태 코드가 아니라 `available` 값만 보고 회색 "정보 없음" 배지를 보여줄지 판단한다. `/congestion` 엔드포인트가 먼저 쓰던 방식을 그대로 따랐다.

## 7. 사용한 기술

| 기술 | 용도 |
|---|---|
| Open-Meteo Forecast API | 무료, API 키 불필요, WGS84 위경도를 직접 받는다 |
| WMO(세계기상기구) 날씨 코드 | 날씨 상태를 숫자로 표현하는 국제 표준 코드 |
| `TTLCache` (메모리 캐시) | 같은 좌표를 5분 안에 다시 조회하면 API를 다시 부르지 않고 캐시된 값을 즉시 반환 |

## 8. 문제와 해결

- **문제:** 지도 화면 브리핑 카드에는 실제 기온 배지가 새로 붙었는데, 바로 아래 요약 문구는 여전히 "☀️ 쾌적한 날씨, 여유로운 혼잡도 — 지금 방문 추천!"으로 고정돼 있어서 같은 카드 안에서 서로 다른 말을 하게 됐다.
- **원인:** 이번 작업 범위가 "배지 교체"였고 그 옆 요약 문구는 범위 밖으로 남겨뒀는데, 배지만 진짜 데이터가 되면서 남아있던 하드코딩 문구가 오히려 더 눈에 띄게 틀린 말이 됐다.
- **해결:** 이번 작업에서는 고치지 않고 관찰(QA 리포트 O1)로만 남겼다. 고칠 때는 카드에 이미 있는 `_weatherFuture`/`_congestionFuture` 값을 조합해서 문구를 만들거나, 두 값이 도착하기 전에는 그 문구 자체를 안 그리는 방법이 있다.
- **배운 점:** 화면 일부를 mock에서 실제 데이터로 바꿀 때, 그 옆에 있는 다른 하드코딩 텍스트가 새 실제값과 모순되지 않는지 같이 확인해야 한다. 배지 하나만 고치고 옆 문구를 안 보면, 고치기 전보다 더 눈에 띄는 모순이 생길 수 있다. 이 교훈은 `.claude/skills/livespot-contract/references/bug-patterns.md` 8절에 일반화해서 추가했다.

## 9. 의사결정

### 사용자가 준 정책 (원문)

> 날씨 제공자는 Open-Meteo Forecast API다. OpenWeatherMap 호출 코드는 제거한다.
> API 키를 사용하지 않는다. config.py에 새 설정을 추가하지 않는다. Open-Meteo 비상업 사용은 키가 필요 없다.
> 요청 파라미터는 latitude, longitude, current=temperature_2m,weather_code 를 사용한다. 응답의 current.temperature_2m(섭씨)와 current.weather_code(WMO 코드)만 읽는다.
> 앱은 Open-Meteo를 직접 호출하지 않는다. 모든 외부 API 호출은 백엔드를 통한다.
> WMO 코드 → 한국어 문구 변환은 서버가 한다. 앱은 문구를 그대로 그린다. 앱이 weather_code 숫자를 직접 해석하는 코드를 쓰지 않는다.
> 날씨 조회가 실패해도 상세페이지의 다른 섹션은 정상 렌더링된다. 날씨 영역만 fallback 문구로 대체된다.
> 장시간 캐싱을 하지 않는다. DB에 저장하지 않는다.

(출처: `_workspace/01_spec.md` 2절. "[사용자정책]" 태그가 붙은 문장을 그대로 옮겼다.)

### 정책에 없어서 확정한 것

| 쟁점 | 결정 | 근거 |
|---|---|---|
| 기존 `WeatherInfo` 스키마 교체 vs 확장 | **확장** (`humidity`를 Optional로 완화, `weather_code`·`icon`·`available` 추가, `temp`/`description` 필드명 유지) | 새 스키마를 따로 만들면 `gemini.py`가 참조하는 필드와 이름이 갈라져서 기능 10 때 다시 합쳐야 한다. 확장 쪽은 `gemini.py`를 한 줄도 안 고치고 계속 동작한다 |
| 상세페이지 표시 위치 | **헤더 이미지 오버레이 배지** (새 섹션 신설 안 함) | 정보량이 "기온 + 아이콘" 둘뿐이라 섹션 하나를 새로 만들 분량이 아니고, 기존 섹션 순서를 하나도 밀지 않는다 |
| 실패 시 응답 형태 | **항상 200 + `available:false`** (503 등 에러 코드 안 씀) | `/congestion` 엔드포인트가 이미 이 방식이라 상세페이지 코드가 한 가지 패턴으로 통일된다 |
| 캐싱 여부 | **5분 메모리 캐시(`TTLCache`)** | "장시간 캐싱 금지"라는 정책 문구를 시간~일 단위로 해석했다. 기온 값은 몇 분 지연돼도 사용자가 체감하지 못하고, 001 일지에서도 같은 수준(분 단위)의 캐시를 이미 허용한 전례가 있다 |
| 지도 화면 브리핑 카드의 28도 하드코딩도 같이 고칠지 | **같이 고침** | 상세페이지만 진짜 날씨가 되면 "지도는 항상 28도 맑음, 상세는 실제 날씨"라는 모순이 같은 앱 안에서 바로 눈에 띄기 때문 |

## 10. 배운 것

- **죽어 있는 코드는 "연결 안 된 코드"와 구분해야 한다.** `weather.py`는 파일은 있었지만 import하는 곳이 0곳이라 사실상 없는 코드나 마찬가지였다. 설계서 그림(`function.md` 2장)에 등장한다고 해서 실제로 동작 중이라고 믿으면 안 되고, 코드를 직접 grep해서 확인해야 한다.
- **필드 이름이 x/y처럼 방향성을 안 가진 이름일 때가 진짜 함정이다.** `mapx`/`mapy`처럼 이름만 봐서는 어느 게 위도고 경도인지 알 수 없는 필드는, 실제로 두 값을 바꿔 넣어도 컴파일 에러가 안 난다. 이런 필드는 QA에서 실측(직접 좌표를 넣어 결과가 상식과 맞는지 확인)으로 검증해야 한다.

## 11. 현재 한계

- **`briefing_card.dart`의 요약 문구가 여전히 하드코딩** — 배지는 실제 기온을 보여주지만 그 아래 요약 문장은 "쾌적한 날씨, 여유로운 혼잡도"로 고정돼 있어 실제 데이터와 모순될 수 있다 (QA 관찰 O1). 고칠 때는 기존 `_weatherFuture`/`_congestionFuture` 값을 조합하면 된다.
- **`gemini.py`가 날씨 없음(`temp=null`)을 아직 처리하지 못함** — 지금은 AI 브리핑이 날씨를 실제로 넘겨받지 않아서 발현하지 않지만, 기능 10에서 날씨를 배선하는 순간 `"None도, 정보 없음"` 같은 문자열이 프롬프트에 들어갈 수 있다 (QA 관찰 O2). 기능 10 착수 시 `weather.temp is not None` 조건을 추가해야 한다.
- **쓰지 않는 `OPENWEATHER_API_KEY` 설정이 3곳(`config.py`, `.env`, `.env.example`)에 그대로 남아 있음** (QA 관찰 O3). 특히 `.env.example`은 아직도 OpenWeatherMap 키가 필요한 것처럼 보여서 헷갈릴 수 있다. 삭제 권고.
- **`flutter analyze`를 이 환경에서 돌릴 수 없음** — 프로젝트 경로에 한글(`경희대`, `공모전`)이 섞여 있어 analysis server가 죽는다. 대신 `dart analyze`로 대체 검증했고, 이번 작업이 새로 만든 파일들의 지적은 0건이었다 (QA 미검증 M1, 코드 문제가 아니라 환경 문제로 확인됨).
- **헤더 배지가 실제 화면에서 어떻게 보이는지 직접 확인하지 않음** — 특히 `SliverAppBar`가 스크롤로 접혔을 때 배지가 다른 아이콘과 겹치거나 잘리는지는 앱을 직접 띄워봐야 안다 (QA 미검증 M2). 사용자가 확인할 때는 hot reload가 아니라 앱을 완전히 재시작해야 스키마 변경이 반영된다.

## 12. 다음 단계

- 기능 10(AI 브리핑)에서 이번에 만든 `WeatherInfo`를 그대로 재료로 써서 실제 브리핑 문구를 생성한다. 이때 `gemini.py`의 None 처리(위 O2)를 먼저 고쳐야 한다.
- `briefing_card.dart`의 하드코딩된 요약 문구를 실제 날씨·혼잡도 값 기반으로 교체 (위 O1).
- 죽은 `OPENWEATHER_API_KEY` 설정 3곳 정리 (위 O3).
- 사용자가 앱을 직접 실행해 헤더 배지의 실제 렌더링(특히 스크롤 접힘 상태)을 확인.
