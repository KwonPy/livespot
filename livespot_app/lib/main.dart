import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 개발용 테스트유저 헤더 복원. runApp보다 먼저 해야 앱 시작 직후의 알림 폴링·Credit
  // 조회가 기본 test_user로 한 번 나가는 창이 없어진다.
  //
  // **`kDebugMode` 가드는 필수다**(QA 1회차 F2). 이 값은 `AuthService.hasServerIdentity`를
  // true로 만들어 로그인 게이트 11곳을 전부 통과시킨다. 가드가 없으면 같은 origin에서
  // 디버그 빌드를 한 번이라도 띄운 브라우저(로컬 `localhost:8080`은 `flutter run`과
  // `flutter build web` 서빙이 같은 origin이다)에서 릴리스 빌드가 그 값을 되살려,
  // 화면은 "로그인하세요"인데 게이트는 통과하고 모든 요청이 401로 떨어진다.
  // 서버가 `TEST_MODE=false`에서 헤더를 무시하므로 보안 구멍은 아니지만(AC6),
  // 원인을 찾기 가장 어려운 종류의 상태다.
  //
  // 이 값을 쓰는 쪽(`profile_screen`의 드롭다운)도 `kDebugMode` 가드다 — 대칭을 맞춘다.
  if (kDebugMode) {
    final prefs = await SharedPreferences.getInstance();
    final savedTestUserId = prefs.getString(AuthService.testUserPrefsKey);
    if (savedTestUserId != null) {
      ApiService.testUserId = savedTestUserId;
    }
  }

  // 로그인 상태 유지(P19). **runApp보다 먼저 기다린다** — 앱이 그려진 뒤에 복원하면
  // 첫 프레임에서 "로그인하세요"가 한 번 번쩍이고, 그보다 나쁘게는 알림 폴링·WS가
  // 비로그인으로 한 번 나갔다가(전부 401) 다시 붙는 창이 생긴다.
  //
  // 토큰이 없으면 네트워크를 타지 않으므로 비로그인 사용자의 시작이 느려지지 않는다.
  // 복원 실패(네트워크)는 예외로 새지 않고 AuthService.restoreError에 남는다 —
  // 여기서 앱 기동을 막으면 서버가 잠깐 죽었을 때 앱이 아예 안 뜬다.
  await AuthService().restore();

  runApp(
    const ProviderScope(
      child: LiveSpotApp(),
    ),
  );
}
