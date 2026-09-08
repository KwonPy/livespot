import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import 'question_detail_sheet.dart';

class _GlobalQaItem {
  final Question question;
  final String spotTitle;
  _GlobalQaItem({required this.question, required this.spotTitle});
}

/// Live 페이지의 "전체 LIVE Q&A" — 관광지 구분 없이 오늘(KST) 등록된 활성 질문을
/// 최신순으로 보여준다. 정책상 이 목록에서는 누구도 답변할 수 없다 — GPS 인증된
/// 사용자라도 여기서는 답변 버튼 자체를 노출하지 않는다(답변은 "내 현장 Q&A"나
/// 관광지 상세페이지에서만). 카드는 관광지명 + 질문 + 답변 개수만 보여주고, 탭하면
/// 실제 답변 내용을 읽기 전용으로 볼 수 있다.
class GlobalQaList extends StatefulWidget {
  const GlobalQaList({super.key});

  @override
  State<GlobalQaList> createState() => _GlobalQaListState();
}

class _GlobalQaListState extends State<GlobalQaList> {
  late Future<List<_GlobalQaItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
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

  void _openDetail(_GlobalQaItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => QuestionDetailSheet(question: item.question, spotName: item.spotTitle),
    );
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(item),
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
                  Icon(Icons.chat_bubble_outline, size: 14, color: q.answerCount > 0 ? Colors.green : Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    q.answerCount > 0 ? '답변 ${q.answerCount}개' : '답변 대기',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: q.answerCount > 0 ? Colors.green : Colors.orange),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
