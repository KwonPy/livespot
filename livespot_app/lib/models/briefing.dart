/// AI 브리핑 (기능 10) — `GET /api/spots/{content_id}/briefing`의 응답.
///
/// 서버는 관광지 자체가 없을 때(404)를 빼면 **항상 200**을 준다. Gemini 키 오류·타임아웃·
/// 쿼터 소진·재료 부족은 전부 200 + `source`(TEMPLATE/NONE)로 표현되므로, 앱에는 "AI가
/// 실패했다"는 분기가 따로 필요 없다 — `source` 값에 따라 라벨만 달라진다.
///
/// 응답 전 필드가 non-null 보장이라 여기서도 nullable을 쓰지 않는다. 서버가 필수로
/// 선언한 필드를 `?? 기본값`으로 받으면 스키마 불일치가 조용히 숨는다.
class Briefing {
  final String contentId;

  /// 본문 3~4문장. `source == 'NONE'`이면 "첫 제보를 남겨주세요" 류의 안내문이 들어온다.
  /// 화면에 그릴 문장은 이것 하나뿐이다 — 서버에 `summary_line`은 없다.
  final String fullBriefing;

  /// `"AI"` | `"CACHED_AI"` | `"TEMPLATE"` | `"NONE"`.
  /// enum이 아니라 String으로 받는다 — 서버가 나중에 폴백 단계를 늘려도 앱이 파싱에서
  /// 깨지지 않아야 한다(모르는 값은 [isAiGenerated]가 false로 흡수한다).
  final String source;

  /// 캐시 히트여도 **원래 생성 시각**이 유지된다.
  final DateTime generatedAt;

  final BriefingBasedOn basedOn;

  Briefing({
    required this.contentId,
    required this.fullBriefing,
    required this.source,
    required this.generatedAt,
    required this.basedOn,
  });

  /// "Gemini로 생성됨" 라벨을 붙여도 되는지. **실제로 AI가 문장을 쓴 경우에만 true다.**
  ///
  /// TEMPLATE(서버가 재료만 이어 붙인 문장)·NONE(AI 호출 자체를 안 함)에 AI 라벨을
  /// 붙이는 것은 금지돼 있다. 모르는 값이 와도 false — 라벨을 **안 붙이는 쪽이 기본값**이다.
  bool get isAiGenerated => source == 'AI' || source == 'CACHED_AI';

  factory Briefing.fromJson(Map<String, dynamic> json) {
    return Briefing(
      contentId: json['content_id'] as String,
      fullBriefing: json['full_briefing'] as String,
      source: json['source'] as String,
      generatedAt: _parseUtc(json['generated_at'] as String),
      basedOn: BriefingBasedOn.fromJson(json['based_on'] as Map<String, dynamic>),
    );
  }

  /// 서버는 naive UTC를 보낸다("2026-09-06T15:35:47.050148" — Z가 없다).
  /// Z를 붙이지 않으면 DateTime.parse가 로컬 시각으로 오인해 9시간 어긋난다.
  static DateTime _parseUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}

/// 이 브리핑이 실제로 무엇을 보고 쓰였는지. [Briefing]의 중첩 객체라 별도 파일로 두지 않는다.
class BriefingBasedOn {
  final bool hasReport; // 당일(KST) 현장 제보 1건 이상 — 실측
  final bool hasCongestion; // 한국관광공사 방문 집중률 예측값 존재 — 예측
  final bool hasWeather; // 현재 날씨 조회 성공

  BriefingBasedOn({
    required this.hasReport,
    required this.hasCongestion,
    required this.hasWeather,
  });

  factory BriefingBasedOn.fromJson(Map<String, dynamic> json) {
    return BriefingBasedOn(
      hasReport: json['has_report'] as bool,
      hasCongestion: json['has_congestion'] as bool,
      hasWeather: json['has_weather'] as bool,
    );
  }
}
