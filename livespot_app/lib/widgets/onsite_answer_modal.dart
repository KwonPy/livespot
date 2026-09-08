import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../services/badge_tracker.dart';
import '../services/mock_data_service.dart';
import 'badge_earned_dialog.dart';

/// 기능 7(현장 Q&A) 답변 작성. GPS 현장 인증(기능 3)된 사용자만 쓸 수 있다 —
/// 이 모달을 여는 쪽(관광지 상세페이지 / Live 페이지)에서 이미 현재 위치를 받아
/// [lat]/[lng]로 넘겨주고, 실제 인증 판정은 답변 등록 API가 매번 서버에서
/// 다시 계산한다. 답변 수정/삭제 기능은 정책상 제공하지 않는다.
class OnsiteAnswerModal extends StatefulWidget {
  final Question question;
  final String spotName;
  final double lat;
  final double lng;

  const OnsiteAnswerModal({
    super.key,
    required this.question,
    required this.spotName,
    required this.lat,
    required this.lng,
  });

  @override
  State<OnsiteAnswerModal> createState() => _OnsiteAnswerModalState();
}

class _OnsiteAnswerModalState extends State<OnsiteAnswerModal> {
  final TextEditingController _answerController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _answerController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorMessage = '답변 내용을 입력해주세요');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final answer = await ApiService().submitAnswer(
        questionId: widget.question.id,
        content: content,
        lat: widget.lat,
        lng: widget.lng,
      );
      if (!mounted) return;

      // 이 답변으로 뱃지가 올랐는지 확인 — 답변 응답 자체엔 적립 여부가 없어 다시 물어야 한다.
      final newBadge = await BadgeTracker.checkForLevelUp();
      if (!mounted) return;
      if (newBadge != null) {
        await BadgeEarnedDialog.show(context, newBadge);
        if (!mounted) return;
      }
      Navigator.pop(context, answer);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motivationTexts = MockDataService().getMotivationTexts();
    final motivation = motivationTexts.length > 1 ? motivationTexts[1] : '현장에 있는 당신만 답할 수 있어요.';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
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
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [LiveSpotTheme.accentColor.withOpacity(0.1), Colors.orange.shade50]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LiveSpotTheme.accentColor.withOpacity(0.5)),
                ),
                child: Text(
                  motivation,
                  style: const TextStyle(color: LiveSpotTheme.accentColor, fontWeight: FontWeight.bold, fontFamily: 'Pretendard'),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.help_outline, size: 16, color: LiveSpotTheme.primaryColor),
                          const SizedBox(width: 4),
                          Text(widget.spotName, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard', color: LiveSpotTheme.primaryColor)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(widget.question.content, style: const TextStyle(fontSize: 16, fontFamily: 'Pretendard')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text('답변 작성', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 8),
              TextField(
                controller: _answerController,
                maxLength: 200,
                maxLines: 3,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  hintText: '알고 있는 현장 상황을 알려주세요',
                  hintStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Pretendard')),
              ],
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LiveSpotTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Text('답변하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
