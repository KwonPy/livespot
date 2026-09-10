import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/question.dart';
import '../services/location_service.dart';
import 'onsite_answer_modal.dart';

/// 기능 6(현장 사용자 수 집계)의 "답변 유도" 배너 — Q6-A.
///
/// 위치 신호(= `POST /reports/verify-location`) 응답에 실려 온 `pending_questions`를
/// 그대로 그린다. **앱은 이 목록을 따로 조회하지 않는다** — 서버가 이미 "활성 + 답변 0건"
/// 필터를 걸어 상위 5건을 골라 보냈고, 앱이 다시 거르면 서버와 기준이 어긋난다.
///
/// 이 배너가 화면에 존재한다는 것 자체가 "이 사용자는 방금 반경 안에서 현장 인증됐다"는
/// 뜻이다 — 호출부는 `presence_registered == true`인 응답에서만 목록을 보관하므로,
/// 인증되지 않은 사용자에게는 그릴 데이터 자체가 존재하지 않는다(빈 목록 → SizedBox).
/// 답변 흐름은 [OnsiteAnswerModal]을 그대로 재사용한다 — 새 답변 경로를 만들지 않는다.
class PendingQuestionsBanner extends StatefulWidget {
  final List<Question> questions;
  final String spotName;

  /// 답변이 등록됐을 때. 호출부가 Q&A 목록·LIVE 상태를 다시 불러오는 데 쓴다.
  final VoidCallback? onAnswered;

  const PendingQuestionsBanner({
    super.key,
    required this.questions,
    required this.spotName,
    this.onAnswered,
  });

  @override
  State<PendingQuestionsBanner> createState() => _PendingQuestionsBannerState();
}

class _PendingQuestionsBannerState extends State<PendingQuestionsBanner> {
  final LocationService _locationService = LocationService();
  bool _answering = false;

  /// 답변할 때 좌표를 **다시 가져온다.** 위치 신호를 보낸 시점의 좌표를 들고 있다가
  /// 재사용하면, 배너를 띄워둔 채 자리를 뜬 사용자가 옛 좌표로 답변하게 된다.
  /// 최종 판정은 어차피 서버가 하지만(매번 재검증), 앱이 먼저 거짓말을 하지 않게 한다.
  /// [QaSection._openAnswerModal]과 동일한 절차다.
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
      if (answer != null) widget.onAnswered?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('위치를 확인하지 못했어요: ${e.toString().replaceFirst('Exception: ', '')}',
              style: const TextStyle(fontFamily: 'Pretendard')),
        ),
      );
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '현장에 있는 지금, 답변을 기다리는 질문이 ${widget.questions.length}개 있어요',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...widget.questions.map(_buildQuestionRow),
        ],
      ),
    );
  }

  Widget _buildQuestionRow(Question q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q. ${q.content}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Pretendard'),
                ),
                const SizedBox(height: 2),
                Text(
                  q.userNickname,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'Pretendard'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _answering ? null : () => _openAnswerModal(q),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: LiveSpotTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('답변하기', style: TextStyle(fontSize: 12, fontFamily: 'Pretendard', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
