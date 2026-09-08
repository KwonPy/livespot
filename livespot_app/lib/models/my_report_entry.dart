// 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
// 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 기능 12(MyPage) "내 제보" 목록. `GET /api/reports/me` 한 줄.
///
/// [ReportResponse]와 담긴 데이터는 같지만 [spotName]이 조인되어 온다는 점이 다르다 —
/// 백엔드는 로컬 FK 없이 spot_content_id만 저장하므로(설계 원칙 2), 이 화면 전용으로
/// 서버가 TourAPI 조회 결과의 이름을 붙여 내려준다.
class MyReportEntry {
  final String id;
  final String spotContentId;

  /// 조회 실패(삭제된 관광지·일시 장애)면 null — 화면은 이때 [spotContentId]를 폴백으로 쓴다.
  final String? spotName;

  final String crowdednessLevel;
  final String waitingTime;
  final String? parkingStatus;
  final String? comment;
  final bool gpsVerified;
  final DateTime createdAt;

  MyReportEntry({
    required this.id,
    required this.spotContentId,
    this.spotName,
    required this.crowdednessLevel,
    required this.waitingTime,
    this.parkingStatus,
    this.comment,
    required this.gpsVerified,
    required this.createdAt,
  });

  factory MyReportEntry.fromJson(Map<String, dynamic> json) {
    return MyReportEntry(
      id: json['id'] as String,
      spotContentId: json['spot_content_id'] as String,
      spotName: json['spot_name'] as String?,
      crowdednessLevel: json['crowdedness_level'] as String,
      waitingTime: json['waiting_time'] as String,
      parkingStatus: json['parking_status'] as String?,
      comment: json['comment'] as String?,
      gpsVerified: json['gps_verified'] as bool,
      createdAt: _parseUtc(json['created_at'] as String),
    );
  }
}
