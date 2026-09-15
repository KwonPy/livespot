import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';

/// 기능 7(현장 Q&A) 질문 작성. 관광지 상세페이지에서만 열린다(위치 제한은 없음 —
/// 질문자는 원래 멀리 있는 사람). 자유 텍스트만 지원한다(정책) — 아래 빠른 질문
/// 칩은 카테고리가 아니라 텍스트를 채워주는 입력 편의 기능일 뿐이다.
class AskQuestionModal extends StatefulWidget {
  final String spotName;
  final String contentId;

  const AskQuestionModal({super.key, required this.spotName, required this.contentId});

  @override
  State<AskQuestionModal> createState() => _AskQuestionModalState();
}

class _AskQuestionModalState extends State<AskQuestionModal> {
  final TextEditingController _questionController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _quickQuestions = [
    '주차 공간 남아있나요?',
    '입장 대기 몇 분인가요?',
    '현재 사람 많은가요?',
    '실체감 날씨 어떤가요?'
  ];

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _questionController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorMessage = '질문을 입력해주세요');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final question = await ApiService().submitQuestion(
        spotContentId: widget.contentId,
        content: content,
      );
      if (!mounted) return;
      Navigator.pop(context, question);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const Text('❓ 현장에 질문하기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 4),
              Text('${widget.spotName}에 대해 궁금한 점을 물어보세요', style: const TextStyle(color: Colors.grey, fontFamily: 'Pretendard')),
              const SizedBox(height: 24),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickQuestions.map((q) => ActionChip(
                  label: Text(q, style: const TextStyle(fontFamily: 'Pretendard')),
                  onPressed: _isSubmitting ? null : () => setState(() => _questionController.text = q),
                  side: BorderSide(color: Colors.grey.shade300),
                )).toList(),
              ),

              const SizedBox(height: 20),
              TextField(
                controller: _questionController,
                maxLength: 200,
                maxLines: 2,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  hintText: '질문을 입력하세요',
                  hintStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Pretendard')),
              ],
              const SizedBox(height: 8),

              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '현장에 있는 다른 여행자가 답할 수 있어요 (등록 후 2시간 지나면 만료돼요)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: 'Pretendard'),
                    ),
                  ),
                ],
              ),
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
                      : const Text('질문 보내기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
