import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';

class _GlobalQaItem {
  final Question question;
  final String spotTitle;
  _GlobalQaItem({required this.question, required this.spotTitle});
}

/// Live 페이지의 "전체 LIVE Q&A" — 관광지 구분 없이 오늘(KST) 등록된 활성 질문을
/// 최신순으로 보여준다. 정책상 이 목록에서는 누구도 답변할 수 없다 — GPS 인증된
/// 사용자라도 여기서는 답변 버튼 자체를 노출하지 않는다(답변은 "내 현장 Q&A"나
/// 관광지 상세페이지에서만). 카드는 관광지명 + 질문 + 답변 개수만 보여주고, 탭하면
/// 실제 답변 내용을 읽기 전용으로 볼 수 있다 — 바텀시트가 아니라 카드 바로 아래로
/// 펼쳐지는 인라인 아코디언(qa_section.dart와 같은 패턴)이다.
class GlobalQaList extends StatefulWidget {
  /// 이 위젯이 지금 화면에 보이는지. 부모(LiveScreen)가 IndexedStack 탭 안에 살아있는
  /// 동안은 initState가 한 번만 돌므로, 다른 화면(관광지 상세페이지)에서 새 질문을
  /// 등록하고 이 탭으로 돌아와도 목록이 그대로였다 — LiveScreen·MapScreen·ProfileScreen과
  /// 같은 isActive 규약을 따른다.
  final bool isActive;

  const GlobalQaList({super.key, this.isActive = true});

  @override
  State<GlobalQaList> createState() => _GlobalQaListState();
}

class _GlobalQaListState extends State<GlobalQaList> {
  late Future<List<_GlobalQaItem>> _itemsFuture;
  // qa_section.dart와 동일한 아코디언 규약: 한 번에 하나만 펼친다.
  String? _expandedQuestionId;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
  }

  @override
  void didUpdateWidget(covariant GlobalQaList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      setState(() {
        _itemsFuture = _loadItems();
      });
    }
  }

  Future<List<_GlobalQaItem>> _loadItems() async {
    final questions = await ApiService().fetchRecentQuestions(limit: 10);
    final uniqueIds = questions.map((q) => q.spotContentId).toSet();
    final titleEntries = await Future.wait(uniqueIds.map((id) async {
      final detail = await ApiService().fetchSpotDetail(id);
      return MapEntry(id, detail?['title'] as String? ?? id);
    }));
    final titleMap = Map.fromEntries(titleEntries);
    return questions.map((q) => _GlobalQaItem(question: q, spotTitle: titleMap[q.spotContentId] ?? q.spotContentId)).toList();
  }

  void _toggleExpand(String questionId) {
    setState(() {
      _expandedQuestionId = _expandedQuestionId == questionId ? null : questionId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text('❓ 전체 LIVE Q&A', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
        ),
        FutureBuilder<List<_GlobalQaItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('지금 등록된 질문이 없어요', style: TextStyle(color: Colors.grey, fontFamily: 'Pretendard'))),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildCard(items[index]),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCard(_GlobalQaItem item) {
    final q = item.question;
    final expanded = _expandedQuestionId == q.id;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleExpand(q.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '[${item.spotTitle}]',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E88E5), fontFamily: 'Pretendard'),
                    ),
                  ),
                  const Spacer(),
                  Text(Formatters.timeAgo(q.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Q. ${q.content}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Pretendard')),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    q.answerCount > 0 ? '답변 ${q.answerCount}개' : '답변 대기',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: q.answerCount > 0 ? LiveSpotTheme.successColor : LiveSpotTheme.warningColor),
                  ),
                  const Spacer(),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey[400]),
                ],
              ),
              if (expanded) ...[
                const Divider(height: 20),
                _buildAnswersList(q),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // qa_section.dart의 _buildAnswersList와 같은 모양 — 답변 버튼은 이 파일 어디에도
  // 없다(구조적으로 불가, CLAUDE.md 6-1 규칙). 읽기 전용으로 답변만 나열한다.
  Widget _buildAnswersList(Question q) {
    if (q.answers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
        child: Text('아직 답변이 없어요.', style: TextStyle(color: Colors.grey[400], fontFamily: 'Pretendard', fontSize: 13)),
      );
    }
    return Column(
      children: q.answers
          .map((a) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(a.userNickname, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                        const Spacer(),
                        Text(Formatters.timeAgo(a.createdAt), style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(a.content, style: const TextStyle(fontSize: 13, fontFamily: 'Pretendard')),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
