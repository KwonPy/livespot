import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/spot.dart';
import '../utils/distance_calculator.dart';
import 'api_service.dart';
import 'location_service.dart';

/// 기능: 자동 제보 유도 알림 (foreground 전용).
///
/// 백그라운드 GPS 추적이나 OS Geofencing은 쓰지 않는다. 앱이 실행 중이고 사용자가
/// 위치 권한을 허용한 상태에서만, 주기적으로 "현재 위치 → 주변 관광지 → 알림 ON인
/// 관광지 → 50m 이내 진입 여부"를 확인한다.
class ProximityAlertService {
  static const _cooldownKeyPrefix = 'proximity_alert_last_';

  final ApiService _api = ApiService();
  final LocationService _locationService = LocationService();

  /// 조건을 만족하는 관광지가 있으면 그 Spot을, 없으면 null을 반환합니다.
  /// (한 번에 여러 곳이 겹치더라도 알림 스팸을 피하기 위해 가장 가까운 한 곳만 돌려줍니다.)
  Future<Spot?> checkForTrigger() async {
    final position = await _locationService.getCurrentPosition();

    final List<Spot> nearby = await _api.fetchNearbySpots(
      position.latitude,
      position.longitude,
      radius: AppConstants.proximityNearbySearchRadiusM,
    );
    if (nearby.isEmpty) return null;

    final enabledSettings = await _api.fetchNotificationSettings(enabledOnly: true);
    final enabledContentIds = enabledSettings.map((s) => s.contentId).toSet();
    if (enabledContentIds.isEmpty) return null;

    Spot? best;
    double bestDistance = double.infinity;

    for (final spot in nearby) {
      if (!enabledContentIds.contains(spot.contentId)) continue;
      if (spot.latitude == null || spot.longitude == null) continue;

      final distance = DistanceCalculator.calculateDistance(
        position.latitude,
        position.longitude,
        spot.latitude!,
        spot.longitude!,
      );
      if (distance > AppConstants.proximityAlertRadiusM) continue;
      if (await _isOnCooldown(spot.contentId)) continue;

      if (distance < bestDistance) {
        bestDistance = distance;
        best = spot;
      }
    }

    return best;
  }

  /// 알림을 보여준 직후 호출 — 쿨다운 타이머를 갱신합니다 (사용자가 무시해도 갱신됨:
  /// 같은 곳에서 계속 서 있다고 알림이 반복돼서는 안 되므로).
  Future<void> markAlertShown(String contentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_cooldownKeyPrefix$contentId', DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> _isOnCooldown(String contentId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt('$_cooldownKeyPrefix$contentId');
    if (lastMs == null) return false;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) < AppConstants.proximityAlertCooldown;
  }
}
