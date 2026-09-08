class AppConstants {
  static const String apiBaseUrl = 'http://127.0.0.1:8000/api';
  static const int gpsVerificationRadius = 500; // 500 meters

  // 자동 제보 유도 알림 (앱이 foreground일 때만 동작 — 백그라운드/OS Geofencing 없음)
  static const double proximityAlertRadiusM = 50; // 관광지 반경 50m 이내 진입 시 알림
  static const Duration proximityAlertCooldown = Duration(hours: 2); // 같은 관광지 재알림 최소 간격
  static const Duration proximityCheckInterval = Duration(seconds: 60); // foreground 위치 재확인 주기
  static const int proximityNearbySearchRadiusM = 3000; // 주변 관광지 조회 반경

  // LIVE 상태창(기능 5)이 "지금 붐빈다"를 판정하는 시간창. 백엔드 settings.LIVE_WINDOW_HOURS와 맞춰둘 것.
  static const int liveWindowHours = 2;
  
  // Content Type IDs
  static const String typeAttraction = '12';
  static const String typeCulture = '14';
  static const String typeFestival = '15';
  static const String typeSports = '28';
  static const String typeLodging = '32';
  static const String typeShopping = '38';
  static const String typeRestaurant = '39';
}
