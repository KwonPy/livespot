/// 실시간 핫스팟 랭킹(Live 페이지) 한 줄. [basis]가 "REPORT"면 실제 현장 제보 기반(1순위),
/// "CONGESTION"이면 실제 제보가 없어 한국관광공사 방문 집중률 예측으로 대체된 항목(2순위)이다.
/// [displayLevel]은 두 소스를 한 화면에서 정렬·배색하기 위한 통일된 3단계(EASY/NORMAL/BUSY)이고,
/// 문구는 출처에 따라 다르게 표시한다(제보="여유/보통/혼잡", 집중률="여유/보통/높음").
/// 제목/주소는 로컬 캐시가 아니라 서버가 그때그때 TourAPI로 조회해 붙인 값이다.
class HotspotEntry {
  final String contentId;
  final String spotTitle;
  final String? spotAddress;
  final String? spotImageUrl; // TourAPI firstimage. 원본 URL이라 그릴 때는 resolveImageUrl()로 감쌀 것
  final String basis; // REPORT / CONGESTION
  final String displayLevel; // EASY / NORMAL / BUSY
  final int? reportCount; // basis=REPORT일 때만
  final DateTime? lastReportAt; // basis=REPORT일 때만
  final double? congestionRate; // basis=CONGESTION일 때만

  HotspotEntry({
    required this.contentId,
    required this.spotTitle,
    this.spotAddress,
    this.spotImageUrl,
    required this.basis,
    required this.displayLevel,
    this.reportCount,
    this.lastReportAt,
    this.congestionRate,
  });

  bool get isFromReport => basis == 'REPORT';

  factory HotspotEntry.fromJson(Map<String, dynamic> json) {
    return HotspotEntry(
      contentId: json['content_id'] as String,
      spotTitle: json['spot_title'] as String,
      spotAddress: json['spot_address'] as String?,
      spotImageUrl: json['spot_image_url'] as String?,
      basis: json['basis'] as String,
      displayLevel: json['display_level'] as String,
      reportCount: json['report_count'] as int?,
      lastReportAt: json['last_report_at'] == null ? null : _parseUtc(json['last_report_at'] as String),
      congestionRate: (json['congestion_rate'] as num?)?.toDouble(),
    );
  }

  static DateTime _parseUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}
