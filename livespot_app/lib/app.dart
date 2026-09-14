import 'package:flutter/material.dart';
import 'config/navigation.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'widgets/nickname_setup_gate.dart';
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
///
/// 기능 9(카카오 로그인)로 세 번째가 추가됐다:
///
/// 3. **알림의 수명 주기를 로그인 상태에 묶는다(P15·P16·AC7).** 비로그인에서는
///    `/api/notifications`가 401이고 WS는 1008로 끊긴다 — 돌릴 이유가 없다. 그리고
///    사용자가 바뀔 때마다 [NotificationService.resetForUserSwitch]를 불러야 하는데,
///    그 호출을 각 화면(로그인 시트·로그아웃 메뉴·테스트유저 드롭다운)에 흩어 놓으면
///    한 경로에서 빠진다 — 014에서 실제로 난 버그가 그것이다. **여기 한 곳에서만 한다.**
///
/// 앱 전용 닉네임 기능으로 네 번째가 추가됐다:
///
/// 4. **닉네임 강제 모달의 유일한 게이트 지점(P42).** `AuthService.needsNickname`이
///    true인 동안 [NicknameSetupGate]가 Navigator **위에** 존재한다. 카카오 로그인 직후와
///    앱 재시작 후 토큰 복원(`/auth/me`) 직후가 모두 같은 `AuthService` 리스너를 타므로,
///    두 경로에 각각 코드를 둘 필요가 없다 — 016의 F1·F2·F3가 전부 "판정을 여러 화면에
///    흩어 놓아 한쪽만 갱신된" 버그였다. **다른 파일에 `needsNickname` 분기가 생기면
///    그게 재발 신호다.**
class LiveSpotApp extends StatefulWidget {
  const LiveSpotApp({super.key});

  @override
  State<LiveSpotApp> createState() => _LiveSpotAppState();
}

class _LiveSpotAppState extends State<LiveSpotApp> with WidgetsBindingObserver {
  final NotificationService _notifications = NotificationService();
  final AuthService _auth = AuthService();

  /// 지금 알림이 물려 있는 사용자. 값이 **바뀔 때만** 알림 계층을 손댄다.
  ///
  /// [AuthService]는 복원 시작/종료 등으로도 리스너를 깨우므로, 매 알림마다
  /// `resetForUserSwitch()`를 부르면 배지가 깜빡이고 폴링이 중복으로 나간다.
  String? _boundIdentity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_syncNotificationsWithIdentity);
    // main()이 runApp 전에 restore()를 끝내 두므로, 여기서는 이미 확정된 상태로 시작한다.
    _syncNotificationsWithIdentity();
  }

  /// 서버가 나를 식별하는 값. 로그인 사용자면 그 `user_id`, 개발 빌드에서 테스트유저
  /// 헤더만 있으면 그 id, 비로그인이면 null이다 — 셋 다 "알림을 누구 걸로 받을지"를
  /// 결정하므로 하나의 값으로 본다(서버 `deps.py`의 판정 순서와 같다).
  String? get _currentIdentity => _auth.user?.userId ?? ApiService.testUserId;

  void _syncNotificationsWithIdentity() {
    final identity = _currentIdentity;
    if (identity == _boundIdentity) return;
    _boundIdentity = identity;

    if (identity == null) {
      // 로그아웃. 먼저 멈추고(폴링·WS·재연결 타이머) 그 다음 상태를 비운다 —
      // 순서가 뒤집히면 reset이 WS를 다시 붙이고 401 폴링이 한 번 나간다.
      _notifications.stop();
      _notifications.resetForUserSwitch(); // 배지 0으로 초기화(AC7)
      return;
    }

    // 로그인 또는 사용자 전환. start()는 이미 돌고 있으면 아무 일도 하지 않으므로,
    // 실제 전환 처리는 resetForUserSwitch()가 한다(WS 재연결 + 기준선 재설정).
    _notifications.start();
    _notifications.resetForUserSwitch();
  }

  @override
  void dispose() {
    // 웹에서 타이머 누수는 아무 에러 없이 조용히 쌓인다 — 폴링 타이머를 반드시 끊는다.
    _notifications.stop();
    _auth.removeListener(_syncNotificationsWithIdentity);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 탭이 백그라운드로 가 있는 동안 브라우저가 타이머를 늦추므로, 돌아오면 즉시 한 번 읽는다.
    // 배경 동작이라 실패는 조용히 무시한다(P12) — refresh의 예외를 여기서 삼킨다.
    // 비로그인이면 부를 대상 자체가 없다(401) — P15.
    if (state == AppLifecycleState.resumed && _currentIdentity != null) {
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
            // 닉네임 강제 모달. **Stack의 맨 위**라 알림 배너까지 덮는다 — 닉네임을
            // 정하기 전에는 어떤 화면·어떤 알림도 조작할 수 없어야 한다(Q1-A).
            //
            // 라우트가 아니라 레이어인 것이 핵심이다: `Navigator.pop`도 브라우저
            // 뒤로가기도 이걸 닫지 못한다. "닫기 불가"를 조건문이 아니라 구조로
            // 강제한다 — 자세한 이유는 [NicknameSetupGate] 주석 참고.
            //
            // `Positioned.fill`이 바깥인 것은 문법 제약이다 — `Positioned`는 Stack의
            // **직계 자식**이어야 한다. 닉네임이 필요 없을 때 남는 빈 `SizedBox`는
            // 그리는 것도 터치를 가로채는 것도 없다.
            Positioned.fill(
              child: ListenableBuilder(
                listenable: _auth,
                builder: (_, __) =>
                    _auth.needsNickname ? const NicknameSetupGate() : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
      home: const SplashScreen(),
    );
  }
}
