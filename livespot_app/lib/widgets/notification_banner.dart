import 'package:flutter/material.dart';

import '../config/navigation.dart';
import '../config/theme.dart';
import '../models/app_notification.dart';
import '../screens/profile/my_qna_screen.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import '../utils/notification_open.dart';

/// 기능 8의 전역 알림 팝업.
///
/// `app.dart`의 `MaterialApp.builder`가 이 위젯을 화면 최상단에 겹쳐 놓지만, 이 위젯
/// 자체는 아무것도 그리지 않는다([build]가 항상 빈 위젯을 돌려준다) — 실제로 보여주는
/// 것은 [showDialog]로 띄우는 **모달**이다. `rootNavigatorKey`를 쓰는 이유는 그대로다:
/// 어느 탭·상세페이지·바텀시트 위에 있든 `Navigator.of(context)`로 최상위 라우터를 찾을
/// 수 없기 때문이다.
///
/// 2026-09-12 사용자 지침으로 자동 닫힘 배너에서 **모달 다이얼로그**로 바뀌었다 — "확인
/// 안 하고 넘어갈 수 있는 배너"가 아니라 GPS 근접 알림(`home_screen.dart`의
/// `_showOnsiteReportPrompt`)과 같은 무게로 다뤄야 한다는 판단이다. 그래서 자동 닫힘
/// 타이머가 없다 — 사용자가 "나중에" 또는 "확인하기"를 직접 눌러야 닫힌다
/// (`barrierDismissible: false`로 바깥 탭으로도 안 닫히게 막는다).
///
/// **기능 6 배너와의 관계:** 2026-09-13(015)로 Live 화면의 `PendingQuestionsBanner`는
/// 제거됐고, 관광지 상세페이지에만 남아 있다. 이 다이얼로그는 모달이라 그 배너(비모달,
/// 본문 안)와 레이어가 다르다 — 상세페이지에서 둘이 겹치면 이 다이얼로그가 위에 뜨고,
/// 닫으면 아래 화면이 그대로 드러난다.
///
/// **알림 종류(2026-09-13 015 정정):** 여기로 도달하는 알림은 다시 `NEW_QUESTION`(현장
/// 사용자에게 "새 질문이 왔다")과 `NEW_ANSWER`(질문자에게 "답변이 달렸다") **2종**이다.
/// 015가 질문 알림 생성을 멈춰 1종으로 좁혔던 것을 사용자 정정으로 되돌렸다 — 없앨
/// 대상은 **알림 목록 페이지**였지 이 모달이 아니었다(`01_spec.md` 2-2절).
/// ⚠️ 그래도 "알림" 탭은 되살리지 않는다. `NEW_QUESTION`이 `GET /notifications` 응답에
/// 다시 실리는 것은 **이 모달과 배지의 내부 데이터 소스**일 뿐, 사용자에게 보여줄
/// 목록 화면이 생긴다는 뜻이 아니다.
///
/// **재접속 요약(2026-09-12, 사용자 정책 "최대 노출"):** 실시간 알림과 별개로, 세션의
/// 첫 관측에서 이미 쌓여 있던 미읽음이 있으면([NotificationService.backlogUnreadCount])
/// "새 알림 N건" 요약 다이얼로그를 하나만 띄운다. 개별 알림마다 띄우지 않는 이유는 대량일
/// 때 사용자가 다이얼로그를 여러 번 닫아야 하는 번거로움을 피하기 위해서다(사용자 확인).
class NotificationBannerHost extends StatefulWidget {
  const NotificationBannerHost({super.key});

  @override
  State<NotificationBannerHost> createState() => _NotificationBannerHostState();
}

class _NotificationBannerHostState extends State<NotificationBannerHost> {
  final NotificationService _service = NotificationService();

  // 지금 다이얼로그가 떠 있는지. 여러 알림이 겹쳐 도착해도 다이얼로그를 쌓지 않고
  // 하나가 닫힌 뒤에 다음 것을 확인한다 — 모달을 여러 겹 쌓으면 뒤로가기 스택이 꼬인다.
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (_dialogShowing) return;
    // 재접속 요약이 실시간 배너보다 먼저다 — 재접속 요약은 세션당 최대 한 번뿐이고,
    // 실시간 배너는 그 뒤로도 계속 생길 수 있으므로 먼저 처리해 치워 둔다.
    final backlog = _service.backlogUnreadCount;
    if (backlog != null) {
      _showBacklogDialog(backlog);
      return;
    }
    final entry = _service.bannerEntry;
    if (entry == null) return;
    _showNotificationDialog(entry);
  }

  Future<void> _showBacklogDialog(int count) async {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) {
      // 앱 시작 직후 첫 프레임 전이라 Navigator가 아직 안 붙었을 수 있다 — 신호를
      // 버리지 않고 다음 프레임에 다시 시도한다. WS가 연결되면 폴링이 멈춰 그다음
      // notifyListeners가 한동안 안 올 수 있으므로, 여기서 재시도하지 않으면 요약이
      // 그대로 유실된다(QA F3).
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _onServiceChanged());
      return;
    }
    _dialogShowing = true;

    final openIt = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (dialogContext) => _BacklogSummaryDialog(count: count),
    );

    _dialogShowing = false;
    // 요약을 봤다는 것과 그 안의 알림들을 읽었다는 것은 다르다 — 서버 상태는 안 건드린다.
    _service.dismissBacklogSummary();
    if (openIt == true && navContext.mounted) {
      // 내 Q&A의 **첫 탭(내가 쓴 질문)**으로 보낸다. 요약이라 특정 질문 하나로 갈 수
      // 없고, 2026-09-13(015)로 "알림" 탭(옛 인덱스 2)이 사라져 안 읽은 답변 표시가
      // 질문 카드 자체로 옮겨갔다 — 이제 밀린 알림을 확인하는 곳이 그 탭이다.
      // ⚠️ 탭이 2개뿐이라 여기에 initialTabIndex: 2를 되살리면 즉시 범위 밖으로 터진다.
      await Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const MyQnaScreen()),
      );
    }

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onServiceChanged());
    }
  }

  Future<void> _showNotificationDialog(NotificationEntry entry) async {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) {
      // _showBacklogDialog와 같은 이유로 다음 프레임에 재시도한다(QA F3).
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _onServiceChanged());
      return;
    }
    _dialogShowing = true;

    final openIt = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (dialogContext) => _NotificationDialog(entry: entry),
    );

    _dialogShowing = false;
    // 자동 닫힘이 없어졌으니 "닫음" 자체가 읽음 처리는 아니다(서버 상태는 안 건드린다) —
    // 배너 슬롯만 비운다. "확인하기"를 골랐을 때만 openNotificationTarget이 실제 읽음
    // 처리를 한다.
    _service.dismissBanner();
    if (openIt == true && navContext.mounted) {
      await openNotificationTarget(navContext, entry);
    }

    // 다이얼로그가 떠 있는 동안 새 알림이 도착했을 수 있다 — 닫힌 직후 다시 확인해
    // 밀린 알림이 조용히 묻히지 않게 한다.
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onServiceChanged());
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _BacklogSummaryDialog extends StatelessWidget {
  final int count;

  const _BacklogSummaryDialog({required this.count});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: LiveSpotTheme.primaryColor),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '안 본 사이 알림이 쌓였어요',
              style: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        // 2026-09-13(015 정정): 인앱 알림이 다시 `NEW_QUESTION`·`NEW_ANSWER` 2종이 됐다.
        // 015가 "답변" 하나로 좁혔던 문구를 두 종류를 아우르는 표현으로 되돌린다 —
        // 이 요약은 [NotificationService.backlogUnreadCount](= 서버 `unread_count`)를
        // 그대로 그리고, 그 값은 두 종류의 합이다. 문구만 "답변"이라고 하면 숫자와
        // 내용이 갈린다.
        '새로운 질문·답변 알림이 $count건 있어요.',
        style: const TextStyle(fontFamily: 'Pretendard', fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('닫기', style: TextStyle(fontFamily: 'Pretendard')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: LiveSpotTheme.primaryColor),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('확인하러 가기', style: TextStyle(color: Colors.white, fontFamily: 'Pretendard')),
        ),
      ],
    );
  }
}

class _NotificationDialog extends StatelessWidget {
  final NotificationEntry entry;

  const _NotificationDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // 2026-09-13(015 정정): `NEW_QUESTION` 분기를 **되살렸다.**
      //
      // 015가 이 분기를 지운 전제는 "서버가 `NEW_QUESTION`을 더 이상 만들지 않는다"였는데,
      // 사용자의 의도는 **알림 목록 페이지만 없애라**는 것이었지 새 질문 모달까지 없애라는
      // 뜻이 아니었다(`01_spec.md` 2-2절). 서버가 생성과 `active_join()` 타입 필터를 모두
      // 원복했으므로 두 종류가 다시 여기로 도달한다 — 분기가 없으면 현장 사용자에게
      // "새 질문이 왔다"가 "내 질문에 답변이 달렸어요"로 뒤집혀 보인다.
      title: Row(
        children: [
          Icon(
            entry.isNewAnswer ? Icons.mark_chat_read_outlined : Icons.help_outline,
            color: LiveSpotTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.isNewAnswer ? '내 질문에 답변이 달렸어요' : '새로운 질문이 도착했어요',
              style: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.displaySpotName,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: LiveSpotTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 6),
          // 문구는 서버가 조립해 준 것을 그대로 그린다.
          Text(entry.body, style: const TextStyle(fontFamily: 'Pretendard', fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            Formatters.timeAgo(entry.createdAt),
            style: const TextStyle(fontFamily: 'Pretendard', fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('나중에', style: TextStyle(fontFamily: 'Pretendard')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: LiveSpotTheme.primaryColor),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('확인하기', style: TextStyle(color: Colors.white, fontFamily: 'Pretendard')),
        ),
      ],
    );
  }
}
