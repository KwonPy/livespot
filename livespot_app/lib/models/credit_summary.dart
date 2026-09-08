/// 기능 4(Credit) · 11(뱃지). `GET /api/credits/me` 응답.
///
/// **뱃지 등급 컷·라벨·이모지는 전부 서버가 계산해서 내려준다**(명세 P22·P27).
/// 여기에 등급표 상수를 복제하면 서버 정책이 바뀌는 순간 화면과 실제 등급이 갈린다.
/// 앱은 [CreditBadge.emoji]·[CreditBadge.label]을 그대로 그리기만 한다.
///
/// 서버는 원장이 비어 있어도 200을 주고 `balance: 0` / `total_earned: 0` /
/// 최하위 뱃지로 채워 보낸다(P23). 즉 **빈 상태는 에러가 아니라 정상 렌더 분기**다.
class CreditSummary {
  final String userId;

  /// `users` 조인 결과. 사용자 행이 없어도 서버가 '게스트'로 채워 보내므로 non-null이다
  /// (`services/credit.py:225`). 지금 화면에는 쓰지 않지만 로그인 단계에서 프로필
  /// 카드의 '로그인하세요' 자리를 대체할 값이라 계약대로 받아둔다.
  final String nickname;

  /// 현재 잔액. 소비처가 아직 없어 지금은 [totalEarned]와 항상 같지만,
  /// 나중에 차감이 생겨도 앱을 고치지 않도록 키를 분리해 받는다(명세 C4).
  final int balance;

  /// 누적 적립 총액(양수 행의 합). **뱃지 판정 기준은 잔액이 아니라 이 값**이다(P5).
  final int totalEarned;

  final CreditBadge badge;

  CreditSummary({
    required this.userId,
    required this.nickname,
    required this.balance,
    required this.totalEarned,
    required this.badge,
  });

  factory CreditSummary.fromJson(Map<String, dynamic> json) {
    return CreditSummary(
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String,
      balance: json['balance'] as int,
      totalEarned: json['total_earned'] as int,
      badge: CreditBadge.fromJson(json['badge'] as Map<String, dynamic>),
    );
  }
}

/// `GET /api/credits/me`의 `badge` 객체. 앱은 이 값들을 판정하지 않고 그린다.
class CreditBadge {
  /// 서버 내부 코드(SEEDLING/EXPLORER/…). 화면에는 쓰지 않고 로그·QA 대조용.
  final String code;

  /// 화면에 그대로 출력할 등급명 (예: 'Spot 탐방객').
  final String label;

  /// 화면에 그대로 출력할 이모지 (예: '📍').
  final String emoji;

  /// 이 등급의 하한 누적 크레딧. 앱이 판정에 쓰지 않는다(참고 표시용).
  final int minCredit;

  /// 다음 등급명. **최고 등급이면 null** — 이 셋(next_*)은 함께 null이 된다.
  final String? nextLabel;

  /// 다음 등급의 하한 누적 크레딧.
  final int? nextAt;

  /// 다음 등급까지 남은 점수. 앱이 `next_at - total_earned`를 직접 계산하지 않는다.
  final int? remaining;

  CreditBadge({
    required this.code,
    required this.label,
    required this.emoji,
    required this.minCredit,
    this.nextLabel,
    this.nextAt,
    this.remaining,
  });

  /// 최고 등급 도달 여부. 서버가 next_* 를 비워 보내는 것으로만 판단한다.
  bool get isMax => nextLabel == null;

  factory CreditBadge.fromJson(Map<String, dynamic> json) {
    return CreditBadge(
      code: json['code'] as String,
      label: json['label'] as String,
      emoji: json['emoji'] as String,
      minCredit: json['min_credit'] as int,
      nextLabel: json['next_label'] as String?,
      nextAt: json['next_at'] as int?,
      remaining: json['remaining'] as int?,
    );
  }
}
