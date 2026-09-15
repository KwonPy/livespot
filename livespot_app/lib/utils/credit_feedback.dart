import '../models/question.dart';
import '../models/report.dart';

/// 제보·답변 완료 피드백에서 **크레딧 적립 결과를 문구로 옮기는 단일 지점**.
///
/// 서버가 `credit_earned`(int, 항상 존재) + `credit_skip_reason`(String?, 세 값)을
/// 내려준다(백엔드 계약 1절). 앱은 이 두 값을 **읽어서 고르기만** 한다:
/// - 적립 금액 상수(제보 10 / 답변 5)를 Dart에 복제하지 않는다(01_spec C1).
///   화면에는 서버가 준 `creditEarned`를 그대로 찍는다.
/// - 미적립 사유를 앱이 `gpsVerified`·한도 등으로 역산하지 않는다(C3).
/// - 적립되지 않았으면 "+N 크레딧 적립"을 **띄우지 않는다**(C8) — 0을 적립처럼
///   보이게 하지 않는다.
///
/// 두 모달이 같은 사유 문구 체계를 쓰도록(C12) 여기 한 곳에만 문구를 둔다.
enum CreditAction { report, answer }

/// 적립 안내 절(節). `null`이면 **크레딧에 대해 아무 말도 하지 않는다.**
///
/// `creditEarned == 0 && creditSkipReason == null`은 목록(GET) 응답이거나
/// 서버 설정 오류라는 도달 불가 경로뿐이다(백엔드 계약 1절 "상호 배타 규칙").
/// 알 수 없는 새 사유 코드가 내려와도 같은 경로로 떨어져 조용히 무시된다 —
/// 모르는 코드를 추측해서 잘못된 문구를 띄우는 것보다 안전하다.
String? creditClause(
  CreditAction action, {
  required int creditEarned,
  required String? creditSkipReason,
}) {
  if (creditEarned > 0) return '+$creditEarned 크레딧 적립 🎉';
  switch (creditSkipReason) {
    case 'NOT_VERIFIED':
      return 'GPS 인증이 안 돼 적립되지 않았어요';
    case 'DAILY_LIMIT':
      return '오늘 이 장소는 적립 한도를 채웠어요';
    case 'ALREADY_AWARDED':
      // 제보의 ALREADY_AWARDED는 같은 client_request_id 재제출(01_spec C11)이다.
      // 이때 "이미 적립받았다"고 단정하면 안 된다 — 첫 제보가 한도 초과로 0원이었을
      // 수도 있고, 서버는 재제출 응답에서 원장을 재조회하지 않는다. 확실히 참인
      // 사실("이미 접수됐다")만 말한다.
      return action == CreditAction.report ? '이미 접수된 제보예요' : '이 질문에는 이미 답변하셨어요';
    default:
      return null;
  }
}

/// 제보 완료 스낵바 문구.
///
/// 사유가 없는 경우(도달 불가·목록 재사용)에는 기존 문구를 그대로 유지한다.
String reportCompletionMessage(Report report) {
  final clause = creditClause(
    CreditAction.report,
    creditEarned: report.creditEarned,
    creditSkipReason: report.creditSkipReason,
  );
  if (clause == null) {
    return report.gpsVerified ? '제보 완료! 🎉' : '제보가 저장됐어요 (GPS 미인증)';
  }
  final base = report.gpsVerified ? '제보 완료!' : '제보가 저장됐어요';
  return report.creditEarned > 0 ? '$base $clause' : '$base · $clause';
}

/// 답변 완료 스낵바 문구. 적립 여부와 무관하게 **항상** 하나를 돌려준다(C12).
String answerCompletionMessage(Answer answer) {
  final clause = creditClause(
    CreditAction.answer,
    creditEarned: answer.creditEarned,
    creditSkipReason: answer.creditSkipReason,
  );
  if (clause == null) return '답변이 등록됐어요';
  return answer.creditEarned > 0 ? '답변 등록 완료! $clause' : '답변이 등록됐어요 · $clause';
}
