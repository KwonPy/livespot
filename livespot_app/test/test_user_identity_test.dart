@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:livespot_app/services/api_service.dart';
import 'package:livespot_app/services/auth_service.dart';

/// QA 1회차 F2 회귀 테스트.
///
/// 원래 버그는 "`dev_test_user_id`를 **지우는 코드가 프로젝트 어디에도 없다**"였다.
/// 그 값이 [AuthService.hasServerIdentity]를 true로 만들어 로그인 게이트 11곳을 전부
/// 통과시키므로, 해제 경로가 없으면 비로그인 UX를 재현할 방법 자체가 사라진다.
/// 지우는 경로가 다시 없어지면 여기서 깨진다.
///
/// **웹 전용 테스트다**(`@TestOn('browser')`). `AuthService`가 `KakaoLoginBridge`를 통해
/// `dart:js`를 끌어오기 때문에 VM에서는 컴파일되지 않는다:
///   flutter test --platform chrome test/test_user_identity_test.dart
void main() {
  const key = AuthService.testUserPrefsKey;
  final auth = AuthService(); // 싱글턴

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiService.testUserId = null;
  });

  test('setTestUserId가 런타임 값과 저장값을 함께 세운다', () async {
    await auth.setTestUserId('seed_user_01');

    expect(ApiService.testUserId, 'seed_user_01');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), 'seed_user_01');
    expect(auth.hasServerIdentity, isTrue, reason: '테스트유저 헤더도 식별 경로다(계약 2절 ②)');
  });

  test('setTestUserId(null)이 저장값까지 지운다 — 해제 경로 (F2-a)', () async {
    await auth.setTestUserId('seed_user_01');
    await auth.setTestUserId(null);

    expect(ApiService.testUserId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNull, reason: '저장값이 남으면 다음 실행에서 되살아난다');
    expect(auth.hasServerIdentity, isFalse, reason: '해제 뒤에는 게이트가 다시 막혀야 한다(AC2)');
  });

  test('로그아웃이 테스트유저 헤더까지 버린다 (F2-b / AC7)', () async {
    await auth.setTestUserId('seed_user_01');
    await auth.logout();

    expect(ApiService.testUserId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNull);
    // app.dart의 _currentIdentity가 null이 되어야 알림 폴링·WS가 stop() 분기로 간다.
    expect(auth.user?.userId ?? ApiService.testUserId, isNull);
  });

  test('설정을 바꾸면 리스너가 깨어난다 — app.dart의 알림 재바인딩(P16)', () async {
    var notified = 0;
    void listener() => notified++;
    auth.addListener(listener);
    addTearDown(() => auth.removeListener(listener));

    await auth.setTestUserId('seed_user_01');
    expect(notified, greaterThan(0));

    final afterSet = notified;
    await auth.setTestUserId('seed_user_01'); // 같은 값 — 깨우지 않는다
    expect(notified, afterSet);

    await auth.setTestUserId(null);
    expect(notified, greaterThan(afterSet));
  });
}
