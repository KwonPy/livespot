/// 기능 5(LIVE 상태창). 실제 reports 기반으로 서버가 매번 실시간 계산한 값.
/// presence/questions가 아직 없어서 "현장 인원"·"질문 수"는 내려오지 않는다.
class LiveStatus {
  final String contentId;
  final bool isLive;
  final int recentReportCount;
  final String? currentCrowdedness;
  final String? currentWaitingTime;
  final String? currentParkingStatus;
  final DateTime? lastReportAt;

  LiveStatus({
    required this.contentId,
    required this.isLive,
    required this.recentReportCount,
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
