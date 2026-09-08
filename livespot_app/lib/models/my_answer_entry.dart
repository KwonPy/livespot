// 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
// 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 기능 12(MyPage) "내 Q&A" 중 답변 탭. `GET /api/questions/me/answers` 한 줄.
///
/// 내 답변만으로는 무슨 질문에 단 것인지 알 수 없어, 서버가 원 질문 내용([questionContent])과
/// 관광지 이름([spotName])을 조인해 함께 내려준다.
class MyAnswerEntry {
  final String id;
  final String questionId;
  final String spotContentId;

  /// 조회 실패면 null — 화면은 이때 [spotContentId]를 폴백으로 쓴다.
  final String? spotName;

  final String questionContent;
  final String content;
  final DateTime createdAt;

  MyAnswerEntry({
    required this.id,
    required this.questionId,
    required this.spotContentId,
    this.spotName,
    required this.questionContent,
    required this.content,
    required this.createdAt,
  });

  factory MyAnswerEntry.fromJson(Map<String, dynamic> json) {
    return MyAnswerEntry(
      id: json['id'] as String,
      questionId: json['question_id'] as String,
      spotContentId: json['spot_content_id'] as String,
      spotName: json['spot_name'] as String?,
      questionContent: json['question_content'] as String,
      content: json['content'] as String,
      createdAt: _parseUtc(json['created_at'] as String),
    );
  }
}
