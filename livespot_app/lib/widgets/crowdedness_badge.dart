import 'package:flutter/material.dart';
import '../config/theme.dart';

/// 기능 9. 방문 집중률 "예측" 전용 배지. level은 green/yellow/red(예측 어휘) —
/// 현장 제보(EASY/NORMAL/BUSY)는 별도 라벨 함수(MockDataService.crowdednessLabel)를 쓴다.
class CrowdednessBadge extends StatelessWidget {
  final String level; // 'green', 'yellow', 'red'

  const CrowdednessBadge({super.key, required this.level});

  /// 예측 어휘 라벨. 배지 바깥(요약 문구 등)에서도 **같은 단어**를 쓰도록 공개한다 —
  /// 각자 매핑을 복사해두면 배지와 문구가 서로 다른 말을 하게 된다.
  /// 매핑에 없는 값(unknown 포함)은 null이며, 호출부가 '정보없음'으로 쓸지
  /// 아예 숨길지 결정한다.
  static String? labelFor(String level) {
    switch (level) {
      case 'green':
        return '여유';
      case 'yellow':
        return '보통';
      case 'red':
        return '높음'; // 실측(제보) 배지의 '혼잡'과 의도적으로 다른 어휘
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData icon;

    switch (level) {
      case 'green':
        badgeColor = LiveSpotTheme.successColor;
        icon = Icons.sentiment_satisfied;
        break;
      case 'yellow':
        badgeColor = LiveSpotTheme.warningColor;
        icon = Icons.sentiment_neutral;
        break;
      case 'red':
        badgeColor = LiveSpotTheme.dangerColor;
        icon = Icons.sentiment_dissatisfied;
        break;
      default:
        badgeColor = Colors.grey;
        icon = Icons.help_outline;
    }

    final String label = labelFor(level) ?? '정보없음';

    return Container(
      padding: LiveSpotTheme.badgePadding,
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(LiveSpotTheme.badgeRadius),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: badgeColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
