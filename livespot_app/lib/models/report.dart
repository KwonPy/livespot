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

  /// **이번 요청으로 새로** 적립된 크레딧. `POST /api/reports` 응답에서만 의미가 있고,
  /// 목록(`GET /api/reports`) 응답에서는 항상 0이다 — 목록 화면은 이 값을 읽지 않는다.
  /// 금액(10)을 앱에 복제하지 않기 위해(01_spec C1) 서버가 준 값을 그대로 보관한다.
  final int creditEarned;

  /// 적립되지 않은 이유: `NOT_VERIFIED` / `DAILY_LIMIT` / `ALREADY_AWARDED`.
  /// 적립됐으면 `null`이다(두 필드는 상호 배타 — 백엔드 계약 1절).
  final String? creditSkipReason;

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
    this.creditEarned = 0,
    this.creditSkipReason,
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
      // 서버는 두 키를 항상 내려보내지만(기본값 0/null) 키 부재에 안전하게 읽는다 —
      // 같은 모델을 목록 응답에서도 재사용하기 때문이다(01_spec 5절).
      creditEarned: json['credit_earned'] as int? ?? 0,
      creditSkipReason: json['credit_skip_reason'] as String?,
    );
  }

  // 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
  // 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
  static DateTime _parseUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}
