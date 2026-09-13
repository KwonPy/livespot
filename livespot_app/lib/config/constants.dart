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
  // foreground 위치 재확인 주기. 2026-09-12 60초 → 15초로 단축(체감 지연 개선 요청).
  // 안전한 이유: /spots/nearby가 위경도를 소수점 3자리(~100m)로 반올림한 키로 120초 TTL
  // 캐시를 쓰므로(tour_api.py::get_nearby_spots), 같은 자리에 머무는 동안 주기를 줄여도
  // TourAPI 실제 호출 횟수는 늘지 않는다 — 늘어나는 건 브라우저 GPS 조회 빈도뿐이다.
  // 도보 속도(~1.4m/s)로 50m 반경을 통과하는 데 걸리는 시간을 감안하면 이 이하로는
  // 체감 개선이 급격히 줄어든다.
  static const Duration proximityCheckInterval = Duration(seconds: 15);
  static const int proximityNearbySearchRadiusM = 3000; // 주변 관광지 조회 반경

  // LIVE 상태창(기능 5)이 "지금 붐빈다"를 판정하는 시간창. 백엔드 settings.LIVE_WINDOW_HOURS와 맞춰둘 것.
  static const int liveWindowHours = 2;

  // 현장 사용자 수(기능 6)의 시간창. 백엔드 settings.PRESENCE_WINDOW_MINUTES와 맞춰둘 것.
  // 판정은 전적으로 서버가 한다 — 이 값은 화면 문구("최근 30분 기준")를 만드는 용도이지
  // 앱이 만료를 다시 계산하는 용도가 아니다. 위의 liveWindowHours(2시간)와 서로 다른
  // 시간창이므로 한 줄에 나란히 두지 않는다(P15).
  static const int presenceWindowMinutes = 30;

  // 질문/답변 알림(기능 8)의 인앱 폴링 주기.
  //
  // 서버는 폴링 주기를 지정하지 않는다(응답에 poll_interval_seconds 같은 필드가 없다) —
  // 전적으로 앱이 정하는 값이다.
  //
  // **이 주기가 곧 "지금 접속 중"의 정의다(P23).** 질문 알림은 현장 사용자 중 지금
  // 접속(폴링) 중인 사람에게만 실시간으로 보이고, 접속하지 않았던 사람은 재접속 시
  // 최근 2시간 내 미확인 알림으로 받는다. 별도의 online 상태 컬럼 없이 폴링 주기
  // 하나로 이 구분을 구현하므로, 주기가 길수록 "실시간"이 무뎌진다.
  //
  // 반대편 한계는 호출량이다. GET /api/notifications는 TourAPI를 부르지 않는 경량
  // 엔드포인트라 이 정도 주기는 부담이 없다(그래서 verify-location에 얹지 않고 따로 팠다).
  //
  // P25가 정한 허용 범위는 5~10초다. 이 범위를 벗어나 늘리면 "새 질문이 올라온 걸
  // 지금 있는 사람이 곧바로 본다"는 기능 8의 전제가 깨진다.
  //
  // 2026-09-12부터 이 값은 **WebSocket이 끊겼을 때의 폴백 주기**로 의미가 바뀌었다.
  // WebSocket이 연결돼 있는 동안은 서버가 새 알림 시점에 깨움 신호를 보내므로 이 타이머를
  // 쓰지 않는다(`notification_service.dart` 참고). WS가 끊기면 다음 폴링까지 최대 이만큼
  // 지연되므로, 여전히 P25 범위(5~10초) 안에 있어야 한다.
  static const int notificationPollIntervalSeconds = 7;

  // WebSocket 재연결 시도 간격. 폴백 폴링과 별개로, 끊긴 WS를 계속 다시 붙여 본다 —
  // 재연결에 성공하면 다시 실시간(깨움 신호 기반)으로 돌아가고 폴백 폴링은 멈춘다.
  static const int notificationWsReconnectDelaySeconds = 5;

  // Content Type IDs
  static const String typeAttraction = '12';
  static const String typeCulture = '14';
  static const String typeFestival = '15';
  static const String typeSports = '28';
  static const String typeLodging = '32';
  static const String typeShopping = '38';
  static const String typeRestaurant = '39';
}
