import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/my_answer_entry.dart';
import '../../models/my_question_entry.dart';
import '../../models/question.dart';
import '../../services/api_service.dart';
import '../../utils/formatters.dart';

/// 기능 12(MyPage) "내 Q&A" — 내가 쓴 질문과 내가 단 답변을 탭으로 나눠 보여준다
/// (메뉴 부제목 "질문 및 답변 이력" 그대로).
///
/// 항목을 탭해도 관광지 상세페이지로 이동하지 않는다(정책 결정) — 읽기 전용 이력이다.
/// 다만 질문 카드는 달린 답변을 펼쳐볼 수 있다 — 별도 이동 없이도 "내가 뭘 물었고
/// 뭐라고 답이 왔는지"를 이 화면 안에서 끝까지 확인할 수 있어야 하기 때문이다.
class MyQnaScreen extends StatefulWidget {
  const MyQnaScreen({super.key});

  @override
  State<MyQnaScreen> createState() => _MyQnaScreenState();
}

class _MyQnaScreenState extends State<MyQnaScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<MyQuestionEntry>> _questionsFuture;
  late Future<List<MyAnswerEntry>> _answersFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _questionsFuture = ApiService().fetchMyQuestions();
    _answersFuture = ApiService().fetchMyAnswers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshQuestions() async {
    setState(() => _questionsFuture = ApiService().fetchMyQuestions());
    await _questionsFuture.then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _refreshAnswers() async {
    setState(() => _answersFuture = ApiService().fetchMyAnswers());
    await _answersFuture.then<void>((_) {}, onError: (Object _) {});
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
  // 질문 탭
  // ---------------------------------------------------------------------------

  Widget _buildQuestionsTab() {
    return RefreshIndicator(
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
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: questions.length,
            itemBuilder: (context, index) => _buildQuestionCard(questions[index]),
          );
        },
      ),
    );
  }

  Widget _buildQuestionCard(MyQuestionEntry q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  q.spotName ?? '관광지 정보 없음 (ID ${q.spotContentId})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LiveSpotTheme.primaryColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (q.isExpired) _statusChip('만료됨', Colors.grey) else _statusChip('진행중', LiveSpotTheme.primaryColor),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q. ${q.content}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
