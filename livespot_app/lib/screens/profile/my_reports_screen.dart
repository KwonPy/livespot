import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/my_report_entry.dart';
import '../../services/api_service.dart';
import '../../services/mock_data_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/gps_verified_badge.dart';

/// 기능 12(MyPage) "내 제보" — 내가 지금까지 남긴 현장 제보를 최신순으로 보여준다.
///
/// 항목을 탭해도 관광지 상세페이지로 이동하지 않는다(정책 결정) — 읽기 전용 이력이다.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<MyReportEntry>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = ApiService().fetchMyReports();
  }

  Future<void> _refresh() async {
    setState(() => _reportsFuture = ApiService().fetchMyReports());
    await _reportsFuture.then<void>((_) {}, onError: (Object _) {});
  }

  Color _crowdColor(String code) => code == 'EASY'
      ? LiveSpotTheme.successColor
      : code == 'NORMAL'
          ? LiveSpotTheme.warningColor
          : LiveSpotTheme.dangerColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(title: const Text('내 제보')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<MyReportEntry>>(
          future: _reportsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (snapshot.hasError) {
              return _errorState(snapshot.error);
            }
            final reports = snapshot.data ?? [];
            if (reports.isEmpty) {
              return _emptyState();
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              itemCount: reports.length,
              itemBuilder: (context, index) => _buildReportCard(reports[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportCard(MyReportEntry r) {
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
          Row(
            children: [
              Expanded(
                child: Text(
                  r.spotName ?? '관광지 정보 없음 (ID ${r.spotContentId})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r.gpsVerified) const Padding(padding: EdgeInsets.only(left: 6), child: GpsVerifiedBadge()),
            ],
          ),
          const SizedBox(height: 4),
          Text(Formatters.reportRecency(r.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chipBadge('혼잡도: ${MockDataService.crowdednessLabel(r.crowdednessLevel)}', _crowdColor(r.crowdednessLevel)),
              _chipBadge('대기: ${MockDataService.waitingTimeLabel(r.waitingTime)}', LiveSpotTheme.primaryColor),
              if (r.parkingStatus != null)
                _chipBadge('주차: ${MockDataService.parkingLabel(r.parkingStatus!)}', _crowdColor(r.parkingStatus!)),
            ],
          ),
          if (r.comment != null && r.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.comment!, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ],
        ],
      ),
    );
  }

  Widget _chipBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 80),
      children: [
        Icon(Icons.edit_note, size: 40, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Center(child: Text('아직 작성한 제보가 없어요', style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '관광지 상세페이지에서 현장 제보를 남겨보세요',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  Widget _errorState(Object? error) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      children: [
        Icon(Icons.error_outline, size: 36, color: Colors.red[300]),
        const SizedBox(height: 12),
        Center(child: Text('제보 목록을 불러오지 못했어요', style: TextStyle(fontSize: 13, color: Colors.red[600], fontWeight: FontWeight.bold))),
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
