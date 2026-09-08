import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/badge_tiers.dart';
import '../models/credit_summary.dart';

/// 뱃지 승급 축하 팝업. 제보·답변 성공 직후 [BadgeTracker.checkForLevelUp]이 승급을
/// 감지하면 이 다이얼로그를 띄운다.
///
/// 뱃지 이미지는 아직 전용 아트가 없어 서버가 준 이모지를 그대로 크게 그린다
/// (다른 화면의 `CreditBadgeChip`과 같은 원칙 — 등급별 세부 디자인은 이후 과제).
class BadgeEarnedDialog extends StatelessWidget {
  final CreditBadge badge;

  const BadgeEarnedDialog({super.key, required this.badge});

  static Future<void> show(BuildContext context, CreditBadge badge) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BadgeEarnedDialog(badge: badge),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 설명 문구는 참고표(kBadgeTiers)에서만 가져온다 — 뱃지 자체(이모지·이름)는
    // 서버 응답을 그대로 쓴다. 알 수 없는 코드가 오면(향후 등급 추가 등) 첫 번째
    // 문구로 대체할 뿐, 화면이 깨지지 않는다.
    final description = kBadgeTiers
        .firstWhere((t) => t.code == badge.code, orElse: () => kBadgeTiers.first)
        .description;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(child: Text(badge.emoji, style: const TextStyle(fontSize: 44))),
            ),
            const SizedBox(height: 16),
            const Text(
              '새 뱃지 획득!',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LiveSpotTheme.primaryColor, fontFamily: 'Pretendard'),
            ),
            const SizedBox(height: 6),
            Text(badge.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontFamily: 'Pretendard'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LiveSpotTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('확인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
