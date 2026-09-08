/// 관광지 실시간 날씨 (GET /api/spots/{content_id}/weather).
///
/// 좌표는 앱이 보내지 않는다 — 서버가 content_id로 TourAPI 좌표를 조회한 뒤
/// Open-Meteo를 호출한다. HOT SPOTS → 상세페이지 경로처럼 Spot.latitude가 null인
/// 진입에서도 동작해야 하기 때문이다.
///
/// 날씨 조회가 실패해도 서버는 항상 200을 준다. 상태 코드가 아니라 [available]로 분기한다.
/// (404는 "관광지 자체가 없음"일 때만 — 그건 예외로 전파된다.)
class WeatherInfo {
  /// 섭씨 기온. 실패 시 null.
  final double? temp;

  /// 한국어 상태 문구. 서버가 WMO 코드를 변환한 결과 — 앱은 그대로 그린다.
  /// 절대 null이 아니다(실패 시 '정보 없음').
  final String description;

  /// 이번 범위 밖이라 항상 null. gemini.py 하위호환용으로 서버가 필드만 유지한다.
  final int? humidity;

  /// WMO 4677 원본 코드. 참고용이며 **앱은 이 숫자를 직접 해석하지 않는다.**
  /// 문구는 [description], 아이콘은 [icon]이 유일한 소스다.
  final int? weatherCode;

  /// 아이콘 키. clear / partly_cloudy / cloudy / fog / drizzle / rain / snow /
  /// shower / thunderstorm / unknown. 절대 null이 아니다(실패 시 'unknown').
  final String icon;

  /// false면 날씨 영역만 fallback 처리한다. 다이얼로그·SnackBar를 띄우지 않는다.
  final bool available;

  const WeatherInfo({
    this.temp,
    required this.description,
    this.humidity,
    this.weatherCode,
    required this.icon,
    required this.available,
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      // temp는 서버 값에 따라 int로 직렬화될 수 있어 num으로 받는다.
      temp: (json['temp'] as num?)?.toDouble(),
      description: json['description'] as String? ?? '정보 없음',
      humidity: (json['humidity'] as num?)?.toInt(),
      weatherCode: (json['weather_code'] as num?)?.toInt(),
      icon: json['icon'] as String? ?? 'unknown',
      available: json['available'] as bool? ?? false,
    );
  }
}
