import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/question.dart';
import '../utils/formatters.dart';

/// 질문 상세 보기(바텀시트, 읽기 전용). 목록 카드는 질문 내용과 답변 개수만 보여주고,
/// 실제 답변 내용은 이 상세를 열어야 확인할 수 있다(정책). 답변 작성 진입점은 여기에
/// 두지 않는다 — "내 현장 Q&A"/상세페이지 Q&A의 답변하기 버튼은 목록 카드에 있고,
/// "전체 LIVE Q&A"에서는 애초에 답변 버튼 자체가 어디에도 없다.
class QuestionDetailSheet extends StatelessWidget {
  final Question question;
  final String? spotName;

  const QuestionDetailSheet({super.key, required this.question, this.spotName});

  @override
  Widget build(BuildContext context) {
    final q = question;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  if (spotName != null)
                    Expanded(
                      child: Text(spotName!,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: LiveSpotTheme.primaryColor, fontFamily: 'Pretendard')),
                    ),
                  if (q.isExpired)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                      child: const Text('만료됨', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                ],
              ),
              SizedBox(height: spotName != null ? 8 : 0),
              Text(q.content, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 4),
              Text('${q.userNickname} · ${Formatters.timeAgo(q.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500], fontFamily: 'Pretendard')),
              const SizedBox(height: 20),
              Text('답변 ${q.answerCount}개', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 8),
              if (q.answers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                  child: Text('아직 답변이 없어요.', style: TextStyle(color: Colors.grey[400], fontFamily: 'Pretendard')),
                )
              else
                ...q.answers.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
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
                    )),
            ],
          ),
        ),
      ),
    );
  }
}
