class AppConstants {
  // 배포 빌드는 --dart-define=API_BASE_URL=https://<railway-backend-domain>/api 로 덮어씀.
  // 값을 주지 않으면 로컬 개발 기본값(127.0.0.1:8000) 사용.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  // 자동 제보 유도 알림 (앱이 foreground일 때만 동작 — 백그라운드/OS Geofencing 없음)
  static const double proximityAlertRadiusM = 50; // 관광지 반경 50m 이내 진입 시 알림
  static const Duration proximityAlertCooldown = Duration(hours: 2); // 같은 관광지 재알림 최소 간격
  static const Duration proximityCheckInterval = Duration(seconds: 60); // foreground 위치 재확인 주기
  static const int proximityNearbySearchRadiusM = 3000; // 주변 관광지 조회 반경

  // LIVE 상태창(기능 5)이 "지금 붐빈다"를 판정하는 시간창. 백엔드 settings.LIVE_WINDOW_HOURS와 맞춰둘 것.
  static const int liveWindowHours = 2;

  // 현장 사용자 수(기능 6)의 시간창. 백엔드 settings.PRESENCE_WINDOW_MINUTES와 맞춰둘 것.
  // 판정은 전적으로 서버가 한다 — 이 값은 화면 문구("최근 30분 기준")를 만드는 용도이지
  // 앱이 만료를 다시 계산하는 용도가 아니다. 위의 liveWindowHours(2시간)와 서로 다른
  // 시간창이므로 한 줄에 나란히 두지 않는다(P15).
  static const int presenceWindowMinutes = 30;


  // Content Type IDs
  static const String typeAttraction = '12';
  static const String typeCulture = '14';
  static const String typeFestival = '15';
  static const String typeSports = '28';
  static const String typeLodging = '32';
  static const String typeShopping = '38';
  static const String typeRestaurant = '39';
}
