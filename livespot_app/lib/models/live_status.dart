/// 기능 5(LIVE 상태창) + 기능 6(현장 사용자 수). 서버가 매번 실시간 계산한 값.
///
/// ⚠️ 이 응답에는 **시간창이 서로 다른 세 그룹**이 섞여 있다. 화면에서 한 줄에 뭉쳐
/// 놓으면 안 된다(P15):
///   - `isLive` / `recentReportCount` : 최근 2시간 (`AppConstants.liveWindowHours`)
///   - `onsiteUserCount`              : 최근 30분 (`AppConstants.presenceWindowMinutes`)
///   - `current*` / `lastReportAt`    : 당일(KST)
class LiveStatus {
  final String contentId;
  final bool isLive;
  final int recentReportCount;

  /// 기능 6. 최근 30분 안에 이 관광지에서 위치 신호를 보낸 **서로 다른 사용자 수**.
  /// Optional이 아니라 int다 — 0("아무도 없음")과 null("모름")을 구분할 필요가 없어
  /// 서버가 `available:false` 폴백을 쓰지 않는다(P14).
  ///
  /// 표기 문구는 반드시 "최근 30분 기준 N명" — "현재 N명"·"실시간 접속"은 금지(P6).
  /// 앱이 켜져 있는지와 무관하게 마지막 신호 시각만으로 판정되므로, "지금 접속 중"이
  /// 아니라 "최근 30분 안에 여기 있었음"이 이 숫자의 정확한 의미다.
  final int onsiteUserCount;

  final String? currentCrowdedness;
  final String? currentWaitingTime;
  final String? currentParkingStatus;
  final DateTime? lastReportAt;

  LiveStatus({
    required this.contentId,
    required this.isLive,
    required this.recentReportCount,
    required this.onsiteUserCount,
    this.currentCrowdedness,
    this.currentWaitingTime,
    this.currentParkingStatus,
    this.lastReportAt,
  });

  factory LiveStatus.fromJson(Map<String, dynamic> json) {
    return LiveStatus(
      contentId: json['content_id'] as String,
      isLive: json['is_live'] as bool,
      recentReportCount: json['recent_report_count'] as int,
      onsiteUserCount: json['onsite_user_count'] as int,
      currentCrowdedness: json['current_crowdedness'] as String?,
      currentWaitingTime: json['current_waiting_time'] as String?,
      currentParkingStatus: json['current_parking_status'] as String?,
      lastReportAt: json['last_report_at'] == null ? null : _parseUtc(json['last_report_at'] as String),
    );
  }

  static DateTime _parseUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}
