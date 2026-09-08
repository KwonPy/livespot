/// 기능 12(MyPage). `GET /api/credits/me/activity` 응답 — 내 활동 건수 요약.
///
/// 크레딧 원장과 별개로 **실제 제보·답변·질문 행 수**를 센 값이다.
/// 적립 상한(장소당 하루 3건)에 걸린 제보도 여기엔 포함되므로,
/// `report_count * 10 == total_earned`가 항상 성립하지는 않는다.
/// 앱이 두 값을 서로 검산하거나 한쪽에서 다른 쪽을 유도하지 않는다.
class ActivityCounts {
  final int reportCount;
  final int answerCount;
  final int questionCount;

  ActivityCounts({
    required this.reportCount,
    required this.answerCount,
    required this.questionCount,
  });

  factory ActivityCounts.fromJson(Map<String, dynamic> json) {
    return ActivityCounts(
      reportCount: json['report_count'] as int,
      answerCount: json['answer_count'] as int,
      questionCount: json['question_count'] as int,
    );
  }
}
