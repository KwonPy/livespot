import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/app_notification.dart';
import '../../models/my_answer_entry.dart';
import '../../models/my_question_entry.dart';
import '../../models/question.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../utils/formatters.dart';

/// 기능 12(MyPage) "내 Q&A" — 내가 쓴 질문 / 내가 단 답변, 두 탭.
///
/// 항목을 탭해도 관광지 상세페이지로 이동하지 않는다(정책 결정) — 읽기 전용 이력이다.
/// 다만 질문 카드는 달린 답변을 펼쳐볼 수 있다 — 별도 이동 없이도 "내가 뭘 물었고 뭐라고
/// 답이 왔는지"를 이 화면 안에서 끝까지 확인할 수 있어야 하기 때문이다.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// **2026-09-13(015) 알림 정책 축소.** 이 화면에 있던 것 두 가지가 사라졌다.
///
///   1. **전역 알림 ON/OFF 토글 카드** — 사용자 정책으로 스위치 자체를 없앴다. 알림은
///      항상 켜져 있고, 앱에 "꺼짐"이라는 상태가 존재하지 않는다(`PushSettings` 모델과
///      `/notifications/push-settings` 호출도 함께 제거).
///   2. **"알림" 탭(3번째 탭)** — 인앱 알림이 `NEW_ANSWER` 1종으로 줄면서 그 목록의
///      내용이 "내가 쓴 질문 중 답변이 달린 것"과 사실상 같아졌다. 같은 사실을 두 곳에
///      그리는 대신 탭을 없애고, 안 읽음 표시를 **질문 카드 자체로 이식**했다.
///
/// 안 읽음 판정은 **서버가 준 `is_read`를 그대로 읽는다** — 앱이 "읽었는지"를 새로
/// 판정하지 않는다. 질문 카드와 알림을 잇는 것은 알림 응답의 `question_id`다.
/// ─────────────────────────────────────────────────────────────────────────────
class MyQnaScreen extends StatefulWidget {
  /// 열릴 때 바로 보여줄 탭(0: 질문, 1: 답변). 기본은 0(첫 탭)이다.
  ///
  /// ⚠️ 탭이 3개에서 2개로 줄었다(015). 2 이상을 넘기면 [TabController]가 범위 밖으로
  /// 즉시 터진다 — 과거의 `initialTabIndex: 2`(알림 탭) 진입점은 전부 0으로 재배선했다.
  final int initialTabIndex;

  const MyQnaScreen({super.key, this.initialTabIndex = 0});

  @override
  State<MyQnaScreen> createState() => _MyQnaScreenState();
}

class _MyQnaScreenState extends State<MyQnaScreen> with SingleTickerProviderStateMixin {
  static const int _tabCount = 2;

  late final TabController _tabController;
  late Future<List<MyQuestionEntry>> _questionsFuture;
  late Future<List<MyAnswerEntry>> _answersFuture;

  final NotificationService _notificationService = NotificationService();
  late Future<void> _notificationListFuture;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      // 호출부가 옛 인덱스(2 = 폐기된 알림 탭)를 넘겨도 화면이 터지지 않게 잘라낸다.
      initialIndex: widget.initialTabIndex.clamp(0, _tabCount - 1),
    );
    _questionsFuture = ApiService().fetchMyQuestions();
    _answersFuture = ApiService().fetchMyAnswers();
    // 화면 진입 시 자동 읽음 처리는 하지 않는다 — 목록을 열었다는 것과 항목을 읽었다는
    // 것은 다르다. 읽음은 질문 카드를 펼치거나 "모두 읽음" 버튼을 눌렀을 때만 일어난다.
    _notificationListFuture = _notificationService.refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshQuestions() async {
    setState(() {
      _questionsFuture = ApiService().fetchMyQuestions();
      // 질문 목록과 "새 답변" 표시는 같은 화면에서 함께 보이는 값이라 같이 갱신한다.
      _notificationListFuture = _notificationService.refresh();
    });
    await _questionsFuture.then<void>((_) {}, onError: (Object _) {});
    await _notificationListFuture.then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _refreshAnswers() async {
    setState(() => _answersFuture = ApiService().fetchMyAnswers());
    await _answersFuture.then<void>((_) {}, onError: (Object _) {});
  }

  // ---------------------------------------------------------------------------
  // 안 읽은 답변 알림 ↔ 질문 매칭
  //
  // 서버가 판정해 준 is_read를 그대로 쓴다. 앱이 하는 일은 question_id가 같은 것을
  // 골라내는 것뿐이고, 무엇이 읽힌 것인지는 앱이 정하지 않는다(계산 금지 원칙).
  // 원본은 NotificationService 하나다 — 이 화면이 따로 목록을 들고 있으면 MyPage
  // 배지와 두 벌이 되어 "배지는 3건인데 표시는 없다"가 생긴다.
  // ---------------------------------------------------------------------------

  List<NotificationEntry> _unreadAnswerNotificationsFor(String questionId) {
    return _notificationService.items
        .where((n) => n.isNewAnswer && !n.isRead && n.questionId == questionId)
        .toList();
  }

  /// 질문 카드를 펼쳐 답변을 실제로 본 시점에 그 질문의 답변 알림을 읽음 처리한다.
  /// 화면을 연 것만으로는 읽음이 아니다.
  Future<void> _onExpandQuestion(String questionId) async {
    final targets = _unreadAnswerNotificationsFor(questionId);
    if (targets.isEmpty) return;
    for (final n in targets) {
      try {
        await _notificationService.markRead(n.id);
      } catch (e) {
        if (!mounted) return;
        // 사용자가 직접 누른 동작의 실패라 조용히 넘기지 않는다(P12).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '읽음 처리에 실패했어요: ${e.toString().replaceFirst('Exception: ', '')}',
              style: const TextStyle(fontFamily: 'Pretendard'),
            ),
          ),
        );
        return;
      }
    }
  }

  Future<void> _onMarkAllRead() async {
    setState(() => _markingAllRead = true);
    try {
      await _notificationService.markAllRead();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '읽음 처리에 실패했어요: ${e.toString().replaceFirst('Exception: ', '')}',
            style: const TextStyle(fontFamily: 'Pretendard'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        title: const Text('내 Q&A'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: LiveSpotTheme.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: LiveSpotTheme.primaryColor,
          tabs: const [Tab(text: '내가 쓴 질문'), Tab(text: '내가 단 답변')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildQuestionsTab(), _buildAnswersTab()],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 질문 탭 (+ 새 답변 알림 표시)
  // ---------------------------------------------------------------------------

  Widget _buildQuestionsTab() {
    return Column(
      children: [
        _buildAnswerAlertBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshQuestions,
            child: FutureBuilder<List<MyQuestionEntry>>(
              future: _questionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                if (snapshot.hasError) {
                  return _errorState(snapshot.error, '질문 목록을 불러오지 못했어요');
                }
                final questions = snapshot.data ?? [];
                if (questions.isEmpty) {
                  return _emptyState(Icons.help_outline, '아직 작성한 질문이 없어요', '관광지 상세페이지에서 궁금한 걸 물어보세요');
                }
                // 알림 상태가 바뀌면(읽음 처리·폴링·WS 신호) 카드 강조가 즉시 따라온다.
                return ListenableBuilder(
                  listenable: _notificationService,
                  builder: (context, _) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      itemCount: questions.length,
                      itemBuilder: (context, index) => _buildQuestionCard(questions[index]),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 질문 목록 위의 한 줄. 알림 조회가 **실패했으면 그 사실을 말하고**, 성공했고 안 읽은
  /// 알림이 있으면 "모두 읽음"을 준다. 실패를 "표시할 게 없음"으로 뭉개면 강조가
  /// 안 뜨는 이유를 화면 어디서도 알 수 없다.
  ///
  /// 숫자는 서버 `unread_count`(= MyPage 배지와 같은 값)를 그대로 그린다. 2026-09-13
  /// (015 정정)부터 그 값은 `NEW_QUESTION`+`NEW_ANSWER` 합이다 — 앱이 답변만 다시 세면
  /// 배지와 두 벌이 된다.
  Widget _buildAnswerAlertBar() {
    return FutureBuilder<void>(
      future: _notificationListFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _answerAlertErrorBanner(snapshot.error);
        }
        return ListenableBuilder(
          listenable: _notificationService,
          builder: (context, _) {
            if (_notificationService.unreadCount == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.mark_chat_unread_outlined, size: 15, color: LiveSpotTheme.primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      // 2026-09-13(015 정정): 서버가 `active_join()`의 타입 필터를 없애
                      // `unread_count`가 다시 `NEW_QUESTION`+`NEW_ANSWER` 합산이 됐다.
                      // 앱에서 답변만 따로 세지 않는다(그러면 MyPage 배지와 갈라진다) —
                      // 대신 **문구를 종류 중립으로** 바꿔 숫자와 말이 어긋나지 않게 한다.
                      // 아래 질문 카드의 "새 답변" 강조는 계속 `NEW_ANSWER`만 대상이므로,
                      // 이 줄의 N이 강조된 카드 수보다 클 수 있다(정상).
                      '안 읽은 알림이 ${_notificationService.unreadCount}건 있어요',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: LiveSpotTheme.primaryColor,
                        fontFamily: 'Pretendard',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _markingAllRead ? null : _onMarkAllRead,
                    child: Text(
                      '모두 읽음',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _markingAllRead ? Colors.grey[350] : LiveSpotTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _answerAlertErrorBanner(Object? error) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '알림 표시를 불러오지 못했어요: ${error.toString().replaceFirst('Exception: ', '')}',
              style: TextStyle(fontSize: 11, color: Colors.red[400]),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _notificationListFuture = _notificationService.refresh()),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('다시 시도',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red[600])),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(MyQuestionEntry q) {
    // 구 "알림" 탭의 안 읽음 표시(테두리 강조 · 본문 볼드 · 파란 점)를 그대로 이식했다.
    final unread = _unreadAnswerNotificationsFor(q.id).isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        // 읽은 카드에도 같은 두께의 투명 테두리를 둔다 — 강조가 켜질 때 카드가 1px
        // 움찔거리지 않게 하려는 것.
        border: Border.all(
          color: unread ? LiveSpotTheme.primaryColor.withValues(alpha: 0.35) : Colors.transparent,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          // 펼쳐서 답변을 본 시점이 곧 읽음이다.
          onExpansionChanged: (expanded) {
            if (expanded) _onExpandQuestion(q.id);
          },
          title: Row(
            children: [
              if (unread)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: LiveSpotTheme.primaryColor, shape: BoxShape.circle),
                ),
              Expanded(
                child: Text(
                  q.spotName ?? '관광지 정보 없음 (ID ${q.spotContentId})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LiveSpotTheme.primaryColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unread) _statusChip('새 답변', LiveSpotTheme.primaryColor),
              if (unread) const SizedBox(width: 4),
              if (q.isExpired) _statusChip('만료됨', Colors.grey) else _statusChip('진행중', LiveSpotTheme.primaryColor),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q. ${q.content}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                    color: unread ? Colors.black87 : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${Formatters.reportRecency(q.createdAt)} · 답변 ${q.answerCount}개',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          children: q.answers.isEmpty
              ? [Text('아직 답변이 없어요', style: TextStyle(fontSize: 12, color: Colors.grey[400]))]
              : q.answers.map(_buildAnswerBubble).toList(),
        ),
      ),
    );
  }

  Widget _buildAnswerBubble(Answer a) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.userNickname, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(a.content, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 답변 탭
  // ---------------------------------------------------------------------------

  Widget _buildAnswersTab() {
    return RefreshIndicator(
      onRefresh: _refreshAnswers,
      child: FutureBuilder<List<MyAnswerEntry>>(
        future: _answersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snapshot.hasError) {
            return _errorState(snapshot.error, '답변 목록을 불러오지 못했어요');
          }
          final answers = snapshot.data ?? [];
          if (answers.isEmpty) {
            return _emptyState(Icons.question_answer_outlined, '아직 작성한 답변이 없어요', '현장에서 다른 사람의 질문에 답해보세요');
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: answers.length,
            itemBuilder: (context, index) => _buildAnswerCard(answers[index]),
          );
        },
      ),
    );
  }

  Widget _buildAnswerCard(MyAnswerEntry a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.spotName ?? '관광지 정보 없음 (ID ${a.spotContentId})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LiveSpotTheme.primaryColor),
          ),
          const SizedBox(height: 6),
          Text('Q. ${a.questionContent}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text('A. ${a.content}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(Formatters.reportRecency(a.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 공용
  // ---------------------------------------------------------------------------

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 80),
      children: [
        Icon(icon, size: 40, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Center(child: Text(title, style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
        const SizedBox(height: 4),
        Center(child: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[400]))),
      ],
    );
  }

  Widget _errorState(Object? error, String title) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      children: [
        Icon(Icons.error_outline, size: 36, color: Colors.red[300]),
        const SizedBox(height: 12),
        Center(child: Text(title, style: TextStyle(fontSize: 13, color: Colors.red[600], fontWeight: FontWeight.bold))),
        const SizedBox(height: 4),
        Center(
          child: Text(
            error.toString().replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.red[400]),
          ),
        ),
      ],
    );
  }
}
