import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/spot.dart';
import '../../services/proximity_alert_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/quick_report_modal.dart';
import '../map/map_screen.dart';
import '../live/live_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const int _mapTabIndex = 0;
  static const int _profileTabIndex = 2;

  final ProximityAlertService _proximityService = ProximityAlertService();
  Timer? _proximityTimer;
  bool _proximityCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startProximityMonitoring();
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드 추적은 하지 않지만, 앱이 다시 foreground로 돌아오면 즉시 한 번 확인한다.
    if (state == AppLifecycleState.resumed) {
      _checkProximityOnce();
    }
  }

  void _startProximityMonitoring() {
    _checkProximityOnce();
    _proximityTimer = Timer.periodic(
      AppConstants.proximityCheckInterval,
      (_) => _checkProximityOnce(),
    );
  }

  Future<void> _checkProximityOnce() async {
    if (_proximityCheckInFlight) return;
    _proximityCheckInFlight = true;
    try {
      final spot = await _proximityService.checkForTrigger();
      if (spot != null && mounted) {
        await _proximityService.markAlertShown(spot.contentId);
        _showOnsiteReportPrompt(spot);
      }
    } catch (_) {
      // 위치 권한이 없거나 서버 호출이 실패해도 화면은 조용히 그대로 유지한다.
    } finally {
      _proximityCheckInFlight = false;
    }
  }

  void _showOnsiteReportPrompt(Spot spot) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('📍 지금 이곳에 계신가요?', style: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.bold)),
        content: Text(
          '${spot.title}\n현장 상황을 10초 만에 알려주세요.\n다른 여행자에게 도움이 됩니다.',
          style: const TextStyle(fontFamily: 'Pretendard'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('나중에', style: TextStyle(fontFamily: 'Pretendard')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: LiveSpotTheme.primaryColor),
            onPressed: () {
              Navigator.pop(dialogContext);
              _openQuickReport(spot);
            },
            child: const Text('지금 제보하기', style: TextStyle(color: Colors.white, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  void _openQuickReport(Spot spot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => QuickReportModal(
        spotName: spot.title,
        spotContentId: spot.contentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MapScreen(isActive: _currentIndex == _mapTabIndex), // 🗺️ 지도 (탐색의 중심 — 주변 조회 & 검색 & 상세 연결)
      const LiveScreen(),                              // 🔴 라이브 (실시간 현황 & 랭킹 & Q&A & 제보)
      // 제보·답변의 크레딧 적립은 그 응답에 드러나지 않는다(백엔드 계약 4절) — 다시
      // 조회해야만 보인다. IndexedStack이 탭을 살려두므로 initState는 한 번뿐이라,
      // 탭이 다시 보일 때 재조회하도록 MapScreen과 같은 isActive 규약을 쓴다.
      ProfileScreen(isActive: _currentIndex == _profileTabIndex), // 👤 마이 (프로필 & Credit)
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
