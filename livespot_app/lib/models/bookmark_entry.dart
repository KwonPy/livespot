// 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
// 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 기능 12(MyPage) "북마크" 목록. `GET /api/bookmarks` 한 줄.
///
/// [MyReportEntry]와 같은 구조 — 백엔드는 로컬 FK 없이 content_id만 저장하므로
/// (설계 원칙 2) 화면에 필요한 관광지 정보는 서버가 TourAPI에서 조인해 붙여준다.
/// TourAPI 조회가 실패한 항목도 목록에서 빠지지 않고 `spot_*`가 전부 null로 온다 —
/// 그때 화면은 '관광지 정보 없음 (ID …)' 폴백을 그리고 탭 이동은 그대로 허용한다.
class BookmarkEntry {
  final String contentId;

  /// 조회 실패(삭제된 관광지·일시 장애)면 null.
  final String? spotName;
  final String? spotAddress;
  final String? spotImageUrl;

  final DateTime createdAt;

  BookmarkEntry({
    required this.contentId,
    this.spotName,
    this.spotAddress,
    this.spotImageUrl,
    required this.createdAt,
  });

  factory BookmarkEntry.fromJson(Map<String, dynamic> json) {
    return BookmarkEntry(
      contentId: json['content_id'] as String,
      spotName: json['spot_name'] as String?,
      spotAddress: json['spot_address'] as String?,
      spotImageUrl: json['spot_image_url'] as String?,
      createdAt: _parseUtc(json['created_at'] as String),
    );
  }
}
