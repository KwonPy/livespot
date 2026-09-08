/// 기능 9. 방문 집중률 "예측" 값 (한국관광공사 TatsCnctrRateService).
/// 과거 방문 패턴 기반 예측치이며, 실시간 현재 상황이 아니다.
/// 현장 제보 기반 실측값(LiveStatus)과는 절대 하나로 합치지 않고 나란히 보여준다.
class CongestionInfo {
  final String? contentId;
  final String? spotName;
  final String? baseYmd;
  final double? congestionRate;
  final String level; // green / yellow / red / unknown — 현장 제보(EASY/NORMAL/BUSY)와 다른 어휘체계
  final String description;

  CongestionInfo({
    this.contentId,
    this.spotName,
    this.baseYmd,
    this.congestionRate,
    required this.level,
    required this.description,
  });

  factory CongestionInfo.fromJson(Map<String, dynamic> json) {
    return CongestionInfo(
      contentId: json['content_id'] as String?,
      spotName: json['spot_name'] as String?,
      baseYmd: json['base_ymd'] as String?,
      congestionRate: (json['congestion_rate'] as num?)?.toDouble(),
      level: json['level'] as String? ?? 'unknown',
      description: json['description'] as String? ?? '정보 없음',
    );
  }
}
