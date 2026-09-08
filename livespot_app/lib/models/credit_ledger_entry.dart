/// 서버는 naive UTC 문자열을 보낸다. Z를 붙이지 않으면 DateTime.parse가
/// 로컬 시각으로 오인해 9시간 어긋난다. (models/question.dart와 같은 패턴)
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 기능 4(Credit). `GET /api/credits/me/ledger` 한 줄 — 통장식 원장 행.
///
/// 잔액 숫자 하나가 아니라 행으로 쌓기 때문에 "왜 줄었죠?"에 답할 수 있다(명세 P1).
/// 회수도 삭제가 아니라 **음수 [amount]** 한 줄로 들어오므로,
/// 화면은 [amount]의 부호를 그대로 반영해야 한다.
class CreditLedgerEntry {
  final String id;

  /// 적립은 양수, 회수는 음수. 앱이 절댓값으로 뭉개지 않는다.
  final int amount;

  /// 적립 사유 코드 (REPORT / ANSWER / …). 표시 문구는 [reasonLabel] 참조.
  final String reason;

  /// 적립을 유발한 대상의 종류 (report / question 등).
  final String sourceType;

  /// 적립을 유발한 대상의 id — 제보 id, 또는 답변 적립이면 **질문 id**
  /// (답변은 질문당 1회 적립이라 `source_id`가 question_id다). 서버 계약상 non-null.
  final String sourceId;

  final DateTime createdAt;

  CreditLedgerEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.sourceType,
    required this.sourceId,
    required this.createdAt,
  });

  /// [reason] 코드의 한국어 표시 문구.
  ///
  /// 서버가 표시 문구를 내려주지 않는 유일한 값이라 여기서 매핑한다
  /// (`CrowdednessBadge.labelFor`와 같은 관례 — 판정이 아니라 표기다).
  /// **모르는 코드는 지어내지 않고 코드 원문을 그대로 보여준다** — 새 사유가
  /// 서버에 추가됐을 때 화면이 조용히 틀린 말을 하지 않게 하기 위한 것이다.
  static String reasonLabel(String reason) {
    switch (reason) {
      case 'REPORT':
        return '현장 제보';
      case 'ANSWER':
        return 'Q&A 답변';
      default:
        return reason;
    }
  }

  factory CreditLedgerEntry.fromJson(Map<String, dynamic> json) {
    return CreditLedgerEntry(
      id: json['id'] as String,
      amount: json['amount'] as int,
      reason: json['reason'] as String,
      sourceType: json['source_type'] as String,
      sourceId: json['source_id'] as String,
      createdAt: _parseUtc(json['created_at'] as String),
    );
  }
}
