import 'package:flutter/material.dart';
import 'config/navigation.dart';
import 'config/theme.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'widgets/notification_banner.dart';

/// 앱 루트. 기능 8(질문/답변 알림) 때문에 두 가지가 추가됐다:
///
/// 1. **전역 폴링의 수명 주기** — [NotificationService]를 여기서 시작하고 여기서 멈춘다.
///    각 화면에서 타이머를 돌리면 화면을 벗어날 때 알림이 끊긴다(기존 `live_screen`의
///    3분 GPS 타이머가 정확히 그런 구조라, 그걸 재사용할 수 없었다).
///
/// 2. **전역 셸(`MaterialApp.builder`)** — 이 앱에는 전역 셸 위젯이 없어서 각 화면이
///    각자 Scaffold를 만든다. 어느 화면에서든 알림 배너를 띄우려면 Navigator보다
///    바깥에 겹칠 계층이 필요하고, 그게 아래 [Stack]이다.
class LiveSpotApp extends StatefulWidget {
  const LiveSpotApp({super.key});

  @override
  State<LiveSpotApp> createState() => _LiveSpotAppState();
}

class _LiveSpotAppState extends State<LiveSpotApp> with WidgetsBindingObserver {
  final NotificationService _notifications = NotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications.start();
  }

  @override
  void dispose() {
    // 웹에서 타이머 누수는 아무 에러 없이 조용히 쌓인다 — 폴링 타이머를 반드시 끊는다.
    _notifications.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 탭이 백그라운드로 가 있는 동안 브라우저가 타이머를 늦추므로, 돌아오면 즉시 한 번 읽는다.
    // 배경 동작이라 실패는 조용히 무시한다(P12) — refresh의 예외를 여기서 삼킨다.
    if (state == AppLifecycleState.resumed) {
      _notifications.refresh().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveSpot',
      debugShowCheckedModeBanner: false,
      theme: LiveSpotTheme.lightTheme,
      navigatorKey: rootNavigatorKey,
      // 배너는 Navigator 위에 **겹쳐** 그린다. Column으로 밀어내면 앱 콘텐츠의
      // 높이가 배너 유무에 따라 달라져서, size.height 기준으로 높이를 잡는
      // 바텀시트들이 오버플로한다.
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const Positioned(left: 0, right: 0, top: 0, child: NotificationBannerHost()),
          ],
        );
      },
      home: const SplashScreen(),
    );
  }
}
