class Report {
  final String id;
  final String userId;
  final String userNickname;
  final String spotContentId;
  final String crowdednessLevel;
  final String waitingTime;
  final String? parkingStatus;
  final String? comment;
  final String? photoUrl;
  final bool gpsVerified;
  final DateTime createdAt;

  Report({
    required this.id,
    required this.userId,
    required this.userNickname,
    required this.spotContentId,
    required this.crowdednessLevel,
    required this.waitingTime,
    this.parkingStatus,
    this.comment,
    this.photoUrl,
    required this.gpsVerified,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userNickname: json['user_nickname'] as String,
      spotContentId: json['spot_content_id'] as String,
      crowdednessLevel: json['crowdedness_level'] as String,
      waitingTime: json['waiting_time'] as String,
      parkingStatus: json['parking_status'] as String?,
      comment: json['comment'] as String?,
      photoUrl: json['photo_url'] as String?,
      gpsVerified: json['gps_verified'] as bool,
      createdAt: _parseUtc(json['created_at'] as String),
    );
  }

  // 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
  // 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
  static DateTime _parseUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}
