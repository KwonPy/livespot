import 'dart:math';

import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/report.dart';
import '../services/api_service.dart';
import '../services/badge_tracker.dart';
import '../services/location_service.dart';
import 'badge_earned_dialog.dart';

const Map<String, String> _crowdednessCodes = {'여유': 'EASY', '보통': 'NORMAL', '혼잡': 'BUSY'};
const Map<String, String> _waitingTimeCodes = {
  '없음': 'NONE',
  '10분 이하': 'UNDER_10',
  '10~30분': '10_TO_30',
  '30분 이상': 'OVER_30',
};
const Map<String, String> _parkingCodes = {'여유': 'EASY', '보통': 'NORMAL', '만차': 'FULL'};

class QuickReportModal extends StatefulWidget {
  final String spotName;
  final String spotContentId;

  const QuickReportModal({super.key, required this.spotName, required this.spotContentId});

  @override
  State<QuickReportModal> createState() => _QuickReportModalState();
}

class _QuickReportModalState extends State<QuickReportModal> {
  String? _selectedCrowdedness;
  String? _selectedWaitingTime;
  String? _selectedParking;
  final TextEditingController _commentController = TextEditingController();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  bool _isSubmitting = false;
  String? _errorMessage;

  // 제보 창을 여는 시점에 한 번만 발급 — 재시도 시에도 같은 값을 써야 서버가 중복 제출을 걸러낸다.
  // 주의: `1 << 32`는 쓰면 안 됨 — Flutter 웹(JS)에서는 비트 시프트가 32비트로 잘려 0이 되고,
  // Random().nextInt(0)이 RangeError를 던진다. 시프트 대신 리터럴 값을 그대로 쓴다.
  late final String _clientRequestId =
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(4294967296)}';

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCrowdedness == null || _selectedWaitingTime == null) {
      setState(() => _errorMessage = '혼잡도와 대기시간은 필수 항목입니다');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final position = await _locationService.getCurrentPosition();
      final Report report = await _apiService.submitReport(
        spotContentId: widget.spotContentId,
        crowdednessLevel: _crowdednessCodes[_selectedCrowdedness]!,
        waitingTime: _waitingTimeCodes[_selectedWaitingTime]!,
        parkingStatus: _selectedParking == null ? null : _parkingCodes[_selectedParking],
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        lat: position.latitude,
        lng: position.longitude,
        clientRequestId: _clientRequestId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.gpsVerified ? '제보 완료! 🎉' : '제보가 저장됐어요 (GPS 미인증)',
            style: const TextStyle(fontFamily: 'Pretendard'),
          ),
        ),
      );

      // 이 제보로 뱃지가 올랐는지 확인 — 제보 응답 자체엔 적립 여부가 없어 다시 물어야 한다.
      final newBadge = await BadgeTracker.checkForLevelUp();
      if (!mounted) return;
      if (newBadge != null) {
        await BadgeEarnedDialog.show(context, newBadge);
        if (!mounted) return;
      }
      Navigator.pop(context, report);
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
              const Text('⚡ 현장 제보하기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 4),
              Text(widget.spotName, style: const TextStyle(color: Colors.grey, fontFamily: 'Pretendard')),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, color: Colors.blue, size: 16),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '📍 제출 시 현재 위치로 GPS 인증됩니다 (반경 100m + 오차 50m, 최대 150m 이내)',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Pretendard'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text('혼잡도 (필수)', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildChip('여유', _selectedCrowdedness, Colors.green, (val) => setState(() => _selectedCrowdedness = val)),
                  _buildChip('보통', _selectedCrowdedness, Colors.orange, (val) => setState(() => _selectedCrowdedness = val)),
                  _buildChip('혼잡', _selectedCrowdedness, Colors.red, (val) => setState(() => _selectedCrowdedness = val)),
                ],
              ),
              const SizedBox(height: 20),

              const Text('대기시간 (필수)', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildChip('없음', _selectedWaitingTime, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedWaitingTime = val)),
                  _buildChip('10분 이하', _selectedWaitingTime, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedWaitingTime = val)),
                  _buildChip('10~30분', _selectedWaitingTime, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedWaitingTime = val)),
                  _buildChip('30분 이상', _selectedWaitingTime, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedWaitingTime = val)),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  const Text('주차 현황 (선택)', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                  const SizedBox(width: 8),
                  Text('주차 가능 관광지만 표시', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: 'Pretendard')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildChip('여유', _selectedParking, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedParking = val)),
                  _buildChip('보통', _selectedParking, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedParking = val)),
                  _buildChip('만차', _selectedParking, LiveSpotTheme.primaryColor, (val) => setState(() => _selectedParking = val)),
                ],
              ),
              const SizedBox(height: 20),

              const Text('한 줄 코멘트 (선택)', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
              const SizedBox(height: 8),
              TextField(
                controller: _commentController,
                maxLength: 30,
                decoration: InputDecoration(
                  hintText: '현장 상황을 한 줄로 알려주세요',
                  hintStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Pretendard')),
              ],

              const SizedBox(height: 16),

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
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('제보하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, String? selectedValue, Color activeColor, Function(String) onSelect) {
    final isSelected = selectedValue == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelect(label),
      selectedColor: activeColor.withOpacity(0.1),
      labelStyle: TextStyle(
        color: isSelected ? activeColor : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontFamily: 'Pretendard'
      ),
      side: BorderSide(color: isSelected ? activeColor : Colors.grey.shade300),
    );
  }
}
