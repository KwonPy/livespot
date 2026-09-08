"""Open-Meteo 기반 현재 날씨 조회.

정책(01_spec.md 2절):
- 제공자는 Open-Meteo Forecast API. **API 키를 쓰지 않는다** (비상업 무키).
- 요청 파라미터는 latitude/longitude/current 3개뿐. 응답에서 current.temperature_2m 와
  current.weather_code 만 읽는다. 예보·습도·강수량은 이번 범위가 아니다.
- 좌표는 WGS84 십진도를 그대로 넣는다. 기상청 격자좌표(nx, ny) 변환을 하지 않는다.
- WMO weather_code → 한국어 문구 변환은 **서버가 한다**(설계원칙 1). 앱은 문구를 그대로 그리고
  아이콘은 별도의 안정적인 `icon` 키로만 고른다 — 한국어 문구를 문자열 매칭하면 문구가 바뀔 때
  조용히 깨진다.
- 실패(타임아웃·비200·파싱 오류)는 예외를 밖으로 던지지 않고 흡수한다. 읽기 경로가 죽으면
  상세페이지 전체가 함께 죽는다(설계원칙 3).
"""

from typing import Optional

from app.models.schemas import WeatherInfo
from app.services.cache import TTLCache
from app.services.http_client import get_session

# 좌표 기준 메모리 캐시 TTL. 관측값은 시간 단위로 갱신되므로 5분 지연은 인지되지 않는다.
# DB에는 저장하지 않는다(공공데이터 로컬 복사 금지 정책).
_CACHE_TTL_SECONDS = 300

# WMO 4677 코드 → (한국어 문구, 아이콘 키). 표에 없는 코드는 UNKNOWN으로 떨어진다.
_UNKNOWN = ("정보 없음", "unknown")

_WMO_CODE_MAP: dict[int, tuple[str, str]] = {
    0: ("맑음", "clear"),
    1: ("구름 조금", "partly_cloudy"),
    2: ("구름 조금", "partly_cloudy"),
    3: ("흐림", "cloudy"),
    45: ("안개", "fog"),
    48: ("안개", "fog"),
    51: ("이슬비", "drizzle"),
    53: ("이슬비", "drizzle"),
    55: ("이슬비", "drizzle"),
    56: ("이슬비", "drizzle"),
    57: ("이슬비", "drizzle"),
    61: ("비", "rain"),
    63: ("비", "rain"),
    65: ("비", "rain"),
    66: ("비", "rain"),
    67: ("비", "rain"),
    71: ("눈", "snow"),
    73: ("눈", "snow"),
    75: ("눈", "snow"),
    77: ("눈", "snow"),
    80: ("소나기", "shower"),
    81: ("소나기", "shower"),
    82: ("소나기", "shower"),
    85: ("눈소나기", "snow"),
    86: ("눈소나기", "snow"),
    95: ("뇌우", "thunderstorm"),
    96: ("뇌우", "thunderstorm"),
    99: ("뇌우", "thunderstorm"),
}


def describe_weather_code(code: Optional[int]) -> tuple[str, str]:
    """WMO weather_code를 (한국어 문구, 아이콘 키)로 변환한다."""
    if code is None:
        return _UNKNOWN
    return _WMO_CODE_MAP.get(int(code), _UNKNOWN)


def unavailable_weather() -> WeatherInfo:
    """조회 실패 시 내려보내는 폴백 객체. 항상 200으로 응답하기 위한 값이다."""
    description, icon = _UNKNOWN
    return WeatherInfo(
        temp=None,
        description=description,
        humidity=None,
        weather_code=None,
        icon=icon,
        available=False,
    )


class WeatherService:
    BASE_URL = "https://api.open-meteo.com/v1/forecast"

    def __init__(self):
        self._cache = TTLCache()

    async def get_current_weather(self, lat: float, lng: float) -> WeatherInfo:
        """좌표의 현재 날씨. 실패해도 예외 대신 available=False 객체를 반환한다.

        주의: lat에는 TourAPI의 mapy가, lng에는 mapx가 들어와야 한다. 뒤집혀도 Open-Meteo가
        에러를 내지 않고 엉뚱한 지점의 기온을 조용히 돌려준다.
        """
        # 소수점 3자리(약 100m)면 같은 관광지의 반복 조회를 한 키로 묶기에 충분하다.
        cache_key = f"{lat:.3f},{lng:.3f}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        params = {
            "latitude": lat,
            "longitude": lng,
            "current": "temperature_2m,weather_code",
        }

        session = get_session()
        try:
            async with session.get(self.BASE_URL, params=params) as response:
                if response.status != 200:
                    return unavailable_weather()
                data = await response.json()

            current = data.get("current") or {}
            temp = current.get("temperature_2m")
            code = current.get("weather_code")
            if temp is None:
                return unavailable_weather()

            description, icon = describe_weather_code(code)
            info = WeatherInfo(
                temp=float(temp),
                description=description,
                humidity=None,
                weather_code=int(code) if code is not None else None,
                icon=icon,
                available=True,
            )
        except Exception:
            # 타임아웃·네트워크 오류·파싱 실패 모두 여기로. 캐시에 담지 않는다(다음 요청에 재시도).
            return unavailable_weather()

        self._cache.set(cache_key, info, ttl_seconds=_CACHE_TTL_SECONDS)
        return info
