import 'package:flutter/material.dart';
import '../models/weather.dart';

/// 관광지 실시간 날씨 배지.
///
/// 아이콘은 **서버가 내려준 `icon` 키로만** 고른다. 예전에는 한국어 `description`을
/// `contains()`로 매칭했는데, 문구가 바뀌면 조용히 기본 아이콘으로 떨어지는 방식이라 폐기했다.
/// `weather_code` 숫자를 앱이 해석하는 일도 없다 — 서버가 이미 변환해서 준다.
class WeatherBadge extends StatelessWidget {
  final WeatherInfo weather;

  /// 헤더 이미지 위에 얹을 때 true. 배경 대비를 위해 그림자/테두리를 더한다.
  final bool onImage;

  /// 축소 배지. 상세페이지 헤더처럼 날씨가 "부수 정보"인 자리에서만 true를 준다.
  ///
  /// 위젯 내부 상수를 직접 줄이지 않고 플래그로 분기하는 이유: 이 위젯은
  /// 지도 화면 브리핑 카드(`briefing_card.dart`)와 공유된다. 기본값을 줄이면
  /// 이번 작업 범위 밖인 그 카드까지 조용히 같이 작아진다.
  final bool compact;

  const WeatherBadge({
    super.key,
    required this.weather,
    this.onImage = false,
    this.compact = false,
  });

  /// 서버 `icon` 키 10종 → Material 아이콘.
  /// 매핑표에 없는 WMO 코드는 서버가 'unknown'으로 내려주므로 default 분기가 그걸 받는다.
  static IconData iconFor(String key) {
    switch (key) {
      case 'clear':
        return Icons.wb_sunny_rounded;
      case 'partly_cloudy':
        return Icons.wb_cloudy_outlined;
      case 'cloudy':
        return Icons.cloud;
      case 'fog':
        return Icons.foggy;
      case 'drizzle':
        return Icons.grain;
      case 'rain':
        return Icons.water_drop;
      case 'snow':
        return Icons.ac_unit;
      case 'shower':
        return Icons.umbrella;
      case 'thunderstorm':
        return Icons.thunderstorm;
      case 'unknown':
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // available:false면 서버가 temp/weather_code를 null로 채워 보낸다.
    // 이 경우에도 다이얼로그/SnackBar는 절대 띄우지 않고 회색 fallback pill만 보여준다.
    final unavailable = !weather.available || weather.temp == null;

    final Color background = unavailable ? const Color(0xFFF5F5F5) : const Color(0xFFFFF8E1);
    final Color border = unavailable ? const Color(0xFFE0E0E0) : const Color(0xFFFFE082);
    final Color foreground = unavailable ? const Color(0xFF757575) : const Color(0xFFE65100);
    final Color iconColor = unavailable ? const Color(0xFF9E9E9E) : const Color(0xFFFFA726);

    final String label = weather.temp == null
        ? weather.description
        : '${weather.temp!.round()}° ${weather.description}';

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: onImage ? Colors.white.withValues(alpha: 0.7) : border.withValues(alpha: 0.5),
        ),
        boxShadow: onImage
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(weather.icon), size: compact ? 10 : 12, color: iconColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
