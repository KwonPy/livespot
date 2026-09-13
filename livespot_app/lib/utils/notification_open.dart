import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/question.dart';
import '../models/spot.dart';
import '../screens/detail/spot_detail_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/question_detail_sheet.dart';

/// 알림을 탭했을 때의 동작 — 배너와 알림 목록 화면이 **같은 함수**를 쓴다.
/// 진입점이 둘이라고 이동 로직을 두 번 쓰면 한쪽만 고쳐지는 날이 온다.
///
/// 하는 일은 두 가지다:
///   1. 읽음 처리(`POST /notifications/{id}/read`)
///   2. 해당 질문 상세로 이동
///
/// 질문 상세는 **기존 [QuestionDetailSheet]를 그대로 재사용**한다(전체 LIVE Q&A가
/// 쓰는 것과 같은 위젯). 답변 버튼이 없는 읽기 전용 시트라, 알림에서 들어온 사용자가
/// GPS 인증 없이 답변할 수 있는 경로가 **구조적으로** 생기지 않는다.
///
/// 서버에는 "질문 1건 조회" 엔드포인트가 없다. 대신 알림이 들고 있는 `spot_content_id`로
/// 그 관광지의 오늘 Q&A 목록을 받아 `question_id`로 찾는다 — 알림 자신은 수명이 없고
/// 연결된 질문이 2시간 유효하므로(P24), 대상 질문은 그 시간 안에는 오늘 목록에 있다.
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
  final questionId = entry.questionId;
  if (questionId == null) {
    // 현재 서버 구현에서 question_id가 null이 되는 경로는 없지만(계약서 1절),
    // 스키마상 Optional이라 관광지 상세로라도 보낸다 — 탭이 아무 일도 안 하게 두지 않는다.
    _pushSpotDetail(context, entry);
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );

  Question? question;
  Object? error;
  try {
    final questions = await ApiService().fetchQuestions(entry.spotContentId);
    for (final q in questions) {
      if (q.id == questionId) {
        question = q;
        break;
      }
    }
  } catch (e) {
    error = e;
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // 로딩 다이얼로그 닫기

  if (error != null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '질문을 불러오지 못했어요: ${error.toString().replaceFirst('Exception: ', '')}',
          style: const TextStyle(fontFamily: 'Pretendard'),
        ),
      ),
    );
    return;
  }

  if (question == null) {
    // 목록에서 못 찾은 경우(날짜 경계 등). 질문 대신 관광지 상세로 보낸다 —
    // "찾을 수 없다"고만 하고 끝내면 사용자가 갈 곳이 없다.
    _pushSpotDetail(context, entry);
    return;
  }

  final found = question;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => QuestionDetailSheet(question: found, spotName: entry.displaySpotName),
  );
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
