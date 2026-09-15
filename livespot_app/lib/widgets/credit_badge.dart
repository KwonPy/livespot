import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/credit_summary.dart';

/// 기능 11(뱃지) 표시 전용 pill. `gps_verified_badge.dart` · `crowdedness_badge.dart`와
/// 같은 시각 언어(작은 pill, 8px radius, 배경 10% + 테두리 30%)를 따른다.
///
/// **이 위젯은 판정하지 않는다.** 서버가 준 [CreditBadge.emoji]와
/// [CreditBadge.label]을 그대로 그릴 뿐이고, 등급 컷 상수도 색 분기도 두지 않는다
/// (명세 P22·P27). 등급별로 색을 다르게 하고 싶어지면 그건 서버 응답에
/// 색 필드가 빠진 것이니 backend에 요청할 일이지 여기서 매핑할 일이 아니다.
class CreditBadgeChip extends StatelessWidget {
  final CreditBadge badge;

  /// 파란 그라데이션 카드처럼 어두운 배경 위에 올릴 때 흰색 계열로 반전한다.
  final bool onDark;

  /// Credit 내역 화면의 요약 카드처럼 더 크게 강조해서 보여줄 때 켠다.
  /// 마이 화면 스탯 행처럼 좁은 칸에 여러 개가 나란히 들어가는 곳은 기본 크기(false)를 쓴다.
  final bool large;

  const CreditBadgeChip({super.key, required this.badge, this.onDark = false, this.large = false});

  @override
  Widget build(BuildContext context) {
    final Color tint = onDark ? Colors.white : LiveSpotTheme.primaryColor;

    return Container(
      padding: large ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8) : LiveSpotTheme.badgePadding,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: onDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(large ? 12 : LiveSpotTheme.badgeRadius),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(badge.emoji, style: TextStyle(fontSize: large ? 20 : 12)),
          SizedBox(width: large ? 6 : 4),
          Flexible(
            child: Text(
              badge.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tint,
                fontSize: large ? 15 : 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
