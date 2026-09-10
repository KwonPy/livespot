import 'question.dart';

/// 기능 4(능동적 현장 인증) + 기능 6(현장 사용자 수 집계)의 응답.
///
/// 이 호출 자체가 곧 "위치 신호"다 — 별도의 presence 전송 API는 없다. 반경 판정을
/// 통과하면 서버가 `presences` 1행을 UPSERT하고(`presence_registered=true`), 그 관광지에서
/// 답변을 기다리는 질문 상위 5건을 함께 실어 보낸다.
///
/// 반경 밖은 **에러가 아니다** — 403이 아니라 200 + `verified:false` / `presence_registered:false`
/// / `pending_questions:[]`로 온다. 앱은 이 응답을 실패로 표시하지 않는다.
class VerifyLocationResult {
  final bool verified;
  final double distanceM;
  final int thresholdM;
  final String message;

  /// 이 신호로 현장 사용자 기록이 실제 갱신됐는지.
  /// 현재는 `verified`와 항상 같은 값이지만 **동일시하지 않는다** — 인증 성공과
  /// 인원 집계 성공은 의미가 다르고 앞으로 어긋날 수 있다(백엔드 계약 1절).
  final bool presenceRegistered;

  /// 답변 대기 질문(활성·답변 0건) 상위 5건. 서버가 빈 배열을 보장하므로 null이 아니다.
  /// 원소는 `GET /api/questions`와 완전히 동일한 모양이라 기존 [Question]을 그대로 쓴다.
  final List<Question> pendingQuestions;

  VerifyLocationResult({
    required this.verified,
    required this.distanceM,
    required this.thresholdM,
    required this.message,
    required this.presenceRegistered,
    required this.pendingQuestions,
  });

  factory VerifyLocationResult.fromJson(Map<String, dynamic> json) {
    return VerifyLocationResult(
      verified: json['verified'] as bool,
      distanceM: (json['distance_m'] as num).toDouble(),
      thresholdM: json['threshold_m'] as int,
      message: json['message'] as String,
      presenceRegistered: json['presence_registered'] as bool,
      pendingQuestions: (json['pending_questions'] as List<dynamic>)
          .map((q) => Question.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }
}
