// 서버는 타임존 없는 UTC 문자열(datetime.utcnow())을 보낸다.
// 'Z'를 붙여 UTC로 명시한 뒤 파싱해야 기기 로컬 시각과의 차이가 정확해진다.
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 기능 7(현장 Q&A)의 답변. GPS 현장 인증된 사용자만 작성할 수 있다.
class Answer {
  final String id;
  final String questionId;
  final String userId;
  final String userNickname;
  final String content;
  final DateTime createdAt;

  /// **이번 요청으로 새로** 적립된 크레딧. `POST /api/questions/{id}/answers` 응답에서만
  /// 의미가 있고, 목록의 `answers[]`에서는 적립받은 답변이라도 항상 0이다 —
  /// 목록 화면은 이 값을 읽지 않는다. 금액(5)은 앱에 복제하지 않는다(01_spec C1).
  final int creditEarned;

  /// 적립되지 않은 이유: `NOT_VERIFIED` / `DAILY_LIMIT` / `ALREADY_AWARDED`.
  /// 적립됐으면 `null`이다(두 필드는 상호 배타 — 백엔드 계약 1절).
  final String? creditSkipReason;

  Answer({
    required this.id,
    required this.questionId,
    required this.userId,
    required this.userNickname,
    required this.content,
    required this.createdAt,
    this.creditEarned = 0,
    this.creditSkipReason,
  });

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      id: json['id'] as String,
      questionId: json['question_id'] as String,
      userId: json['user_id'] as String,
      userNickname: json['user_nickname'] as String,
      content: json['content'] as String,
      createdAt: _parseUtc(json['created_at'] as String),
      // 서버는 두 키를 항상 내려보내지만(기본값 0/null) 키 부재에 안전하게 읽는다 —
      // 같은 모델을 목록 응답의 answers[]에서도 재사용하기 때문이다(01_spec 5절).
      creditEarned: json['credit_earned'] as int? ?? 0,
      creditSkipReason: json['credit_skip_reason'] as String?,
    );
  }
}

/// 기능 7(현장 Q&A)의 질문. 자유 텍스트만 지원(카테고리 없음). 등록 즉시 ACTIVE,
/// 2시간 뒤 EXPIRED(만료돼도 조회는 가능, 새 답변만 불가).
class Question {
  final String id;
  final String userId;
  final String userNickname;
  final String spotContentId;
  final String content;
  final String status; // ACTIVE / EXPIRED
  final int answerCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<Answer> answers;

  Question({
    required this.id,
    required this.userId,
    required this.userNickname,
    required this.spotContentId,
    required this.content,
    required this.status,
    required this.answerCount,
    required this.createdAt,
    required this.expiresAt,
    required this.answers,
  });

  bool get isExpired => status == 'EXPIRED';

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userNickname: json['user_nickname'] as String,
      spotContentId: json['spot_content_id'] as String,
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
