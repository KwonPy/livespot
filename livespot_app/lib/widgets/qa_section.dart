import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/formatters.dart';
import 'ask_question_modal.dart';
import 'onsite_answer_modal.dart';
import 'question_detail_sheet.dart';

/// 기능 7(현장 Q&A) — 답변 가능한 컨텍스트 전용. 관광지 상세페이지와 Live 페이지의
/// "내 현장 Q&A"(GPS 인증된 관광지) 양쪽에서 재사용한다. "전체 LIVE Q&A"(어디서도 답변
/// 불가)는 이 위젯을 쓰지 않고 별도의 읽기 전용 [GlobalQaList]를 쓴다.
///
/// 정책: 질문은 상세페이지에서만 작성 가능(위치 제한 없음) — [showAskButton]으로 노출을
/// 제어한다. 답변은 GPS 현장 인증(기능 3)이 되어야만 가능해서, "답변하기"를 누를 때마다
/// 현재 위치를 새로 가져와 답변 등록 API에 함께 보낸다(서버가 매번 재검증). 카드를 탭하면
/// 실제 답변 내용을 볼 수 있는 상세를 연다 — 목록에는 답변 개수만 보인다.
class QaSection extends StatefulWidget {
  final String spotContentId;
  final String spotName;
  final bool showAskButton;
  // Live 페이지 "내 현장 Q&A"는 활성 질문만 보여준다(정책). 상세페이지는 기본값(false)으로
  // 만료된 질문도 "만료" 배지와 함께 계속 보여준다.
  final bool activeOnly;

  const QaSection({
    super.key,
    required this.spotContentId,
    required this.spotName,
    this.showAskButton = true,
    this.activeOnly = false,
  });

  @override
  State<QaSection> createState() => _QaSectionState();
}

class _QaSectionState extends State<QaSection> {
  late Future<List<Question>> _questionsFuture;
  final LocationService _locationService = LocationService();
  bool _answering = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _questionsFuture = ApiService().fetchQuestions(widget.spotContentId, activeOnly: widget.activeOnly);
    });
  }

  Future<void> _openAskModal() async {
    final question = await showModalBottomSheet<Question>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AskQuestionModal(spotName: widget.spotName, contentId: widget.spotContentId),
    );
    if (question != null) _reload();
  }

  void _openDetail(Question q) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => QuestionDetailSheet(question: q),
    );
  }

  // 답변하기: 매번 현재 위치를 새로 확인해 답변 등록 API로 그대로 넘긴다. 실제 GPS
  // 인증 판정은 서버가 한다 — 여기서 미리 걸러내지 않고, 범위를 벗어나면 모달 안에서
  // 서버가 돌려준 오류 메시지를 그대로 보여준다.
  Future<void> _openAnswerModal(Question question) async {
    if (_answering) return;
    setState(() => _answering = true);
    try {
      final position = await _locationService.getCurrentPosition();
      if (!mounted) return;
      final answer = await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => OnsiteAnswerModal(
          question: question,
          spotName: widget.spotName,
          lat: position.latitude,
          lng: position.longitude,
        ),
      );
      if (answer != null) _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치를 확인하지 못했어요: ${e.toString().replaceFirst('Exception: ', '')}', style: const TextStyle(fontFamily: 'Pretendard'))),
      );
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('❓ 현장 Q&A', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
              const Spacer(),
              if (widget.showAskButton)
                TextButton(
                  onPressed: _openAskModal,
                  child: const Text('질문하기 >', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Question>>(
            future: _questionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final questions = snapshot.data ?? [];
              if (questions.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: Text(
                      '오늘 등록된 질문이 없어요.\n첫 번째로 현장에 물어보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
                );
              }
              return Column(children: questions.map((q) => _buildQaCard(q)).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQaCard(Question q) {
    final canAnswer = !q.isExpired;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDetail(q),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('Q. ${q.content}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    if (q.isExpired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                        child: const Text('만료됨', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(q.userNickname, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 14, color: q.answerCount > 0 ? Colors.green : Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      q.answerCount > 0 ? '답변 ${q.answerCount}개' : '답변 대기',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: q.answerCount > 0 ? Colors.green : Colors.orange),
                    ),
                    const Spacer(),
                    Text(Formatters.timeAgo(q.createdAt), style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ),
                if (canAnswer) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _answering ? null : () => _openAnswerModal(q),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LiveSpotTheme.primaryColor,
                        side: const BorderSide(color: LiveSpotTheme.primaryColor),
                      ),
                      child: const Text('답변하기', style: TextStyle(fontFamily: 'Pretendard', fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
