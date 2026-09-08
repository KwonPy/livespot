import 'question.dart' show Answer;

// 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
// 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 기능 12(MyPage) "내 Q&A" 중 질문 탭. `GET /api/questions/me` 한 줄.
///
/// 스팟별 조회([Question])와 달리 "오늘(KST)만" 필터가 없다 — 개인 활동 이력이므로
/// 지난 질문도 계속 보여야 한다. [spotName]은 이 화면 전용으로 서버가 조인해 내려준다.
class MyQuestionEntry {
  final String id;
  final String spotContentId;

  /// 조회 실패면 null — 화면은 이때 [spotContentId]를 폴백으로 쓴다.
  final String? spotName;

  final String content;
  final String status; // ACTIVE / EXPIRED
  final int answerCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<Answer> answers;

  MyQuestionEntry({
    required this.id,
    required this.spotContentId,
    this.spotName,
    required this.content,
    required this.status,
    required this.answerCount,
    required this.createdAt,
    required this.expiresAt,
    required this.answers,
  });

  bool get isExpired => status == 'EXPIRED';

  factory MyQuestionEntry.fromJson(Map<String, dynamic> json) {
    return MyQuestionEntry(
      id: json['id'] as String,
      spotContentId: json['spot_content_id'] as String,
      spotName: json['spot_name'] as String?,
      content: json['content'] as String,
      status: json['status'] as String,
      answerCount: json['answer_count'] as int,
      createdAt: _parseUtc(json['created_at'] as String),
      expiresAt: _parseUtc(json['expires_at'] as String),
      answers: (json['answers'] as List<dynamic>)
          .map((a) => Answer.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}
