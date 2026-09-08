/// 뱃지 5단계 참고 표 — 안내 문구(설명·기준선) 전용이다.
///
/// **뱃지 판정에는 쓰지 않는다.** 실제로 "지금 내 뱃지가 뭔지"는 항상 서버가 계산해 준
/// [CreditBadge]를 그대로 쓴다(명세 P22·P27, `widgets/credit_badge.dart` 참고). 이 표는
/// Credit 내역 화면 하단의 "다른 등급은 뭐가 있지?" 안내와, 뱃지 획득 팝업의 한 줄 설명에만
/// 쓰인다 — 어느 쪽도 활성/비활성 판정이나 진행률 계산에 이 값을 쓰지 않는다.
///
/// `function.md` 기능 11의 등급표, `services/credit.py`의 `BADGE_TIERS`와 값이 같다.
/// 서버가 등급 컷을 바꾸면 이 표도 함께 갱신해야 하지만, 여기가 틀려도 실제 판정(서버 응답)은
/// 영향받지 않고 안내 문구만 잠깐 어긋난다.
class BadgeTierInfo {
  final String code;
  final String emoji;
  final String label;
  final int minCredit;
  final String description;

  const BadgeTierInfo({
    required this.code,
    required this.emoji,
    required this.label,
    required this.minCredit,
    required this.description,
  });
}

const List<BadgeTierInfo> kBadgeTiers = [
  BadgeTierInfo(
    code: 'SPROUT',
    emoji: '🌱',
    label: '새싹',
    minCredit: 0,
    description: 'LiveSpot에 첫 발을 내디뎠어요',
  ),
  BadgeTierInfo(
    code: 'VISITOR',
    emoji: '📍',
    label: 'Spot 탐방객',
    minCredit: 50,
    description: '현장 제보와 답변으로 정보를 나누기 시작했어요',
  ),
  BadgeTierInfo(
    code: 'EXPLORER',
    emoji: '🧭',
    label: 'Spot 탐험가',
    minCredit: 100,
    description: '꾸준한 활동으로 여러 관광지 정보를 채워가고 있어요',
  ),
  BadgeTierInfo(
    code: 'VETERAN',
    emoji: '🏆',
    label: '베테랑',
    minCredit: 200,
    description: '많은 방문자에게 실질적인 도움을 준 활동가예요',
  ),
  BadgeTierInfo(
    code: 'MASTER',
    emoji: '👑',
    label: '마스터',
    minCredit: 500,
    description: 'LiveSpot 최고 등급, 누구보다 활발한 기여자예요',
  ),
];
