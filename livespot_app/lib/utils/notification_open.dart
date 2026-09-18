import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/spot.dart';
import '../screens/detail/spot_detail_screen.dart';
import '../services/notification_service.dart';

/// 알림을 탭했을 때의 동작 — 배너와 알림 목록 화면이 **같은 함수**를 쓴다.
/// 진입점이 둘이라고 이동 로직을 두 번 쓰면 한쪽만 고쳐지는 날이 온다.
///
/// 하는 일은 두 가지다:
///   1. 읽음 처리(`POST /notifications/{id}/read`)
///   2. 관광지 상세페이지로 이동
///
/// 2026-09-18 사용자 지침으로 질문 상세를 조회해 읽기 전용 [QuestionDetailSheet]를
/// 띄우던 중간 단계를 없앴다. 답변은 어차피 상세페이지의 [QaSection]에서 GPS 재인증을
/// 거쳐야만 가능하므로 — 알림에서 곧장 상세페이지로 보내 그 자리에서 질문을 보고 답변까지
/// 이어지게 한다. 읽기 전용 시트는 "전체 LIVE Q&A" 카드 탭 경로에는 여전히 남아 있다
/// (`qa_section.dart`).
Future<void> openNotificationTarget(BuildContext context, NotificationEntry entry) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  // ── 1. 읽음 처리 ──
  // 실패해도 이동을 막지 않는다. 탭의 목적은 "질문을 보는 것"이고 읽음은 부수효과다.
  // 다만 사용자가 직접 누른 동작이므로 조용히 넘기지 않고 서버 메시지를 그대로 알린다(P12).
  try {
    await NotificationService().markRead(entry.id);
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '읽음 처리에 실패했어요: ${e.toString().replaceFirst('Exception: ', '')}',
          style: const TextStyle(fontFamily: 'Pretendard'),
        ),
      ),
    );
  }

  if (!context.mounted) return;

  // ── 2. 이동 ──
  _pushSpotDetail(context, entry);
}

void _pushSpotDetail(BuildContext context, NotificationEntry entry) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SpotDetailScreen(
        spot: Spot(contentId: entry.spotContentId, title: entry.displaySpotName),
      ),
    ),
  );
}
