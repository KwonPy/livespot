import 'package:flutter/widgets.dart';

/// 앱 전역 Navigator 키.
///
/// `MaterialApp.builder`로 붙인 전역 알림 배너(기능 8)는 **Navigator보다 바깥**에서
/// 그려지기 때문에 `Navigator.of(context)`로 앱의 라우터를 찾을 수 없다. 배너 탭으로
/// 질문 상세를 열려면 이 키를 통해 Navigator에 접근해야 한다.
///
/// 다른 화면은 평소대로 `Navigator.of(context)`를 쓴다 — 이 키는 "화면 바깥에서
/// 이동을 시작해야 하는" 경우 전용이다.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');
