import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'services/api_service.dart';

/// `profile_screen.dart`의 `_prefsKey`와 동일한 키. 테스트유저 전환은 개발용
/// 다인 시연 도구라 ProfileScreen 안에만 있었지만, runApp보다 먼저 복원해야
/// 앱 시작 직후의 알림 폴링·Credit 조회가 기본 test_user로 한 번 나가는 창을 없앤다.
const _testUserPrefsKey = 'dev_test_user_id';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final savedTestUserId = prefs.getString(_testUserPrefsKey);
  if (savedTestUserId != null) {
    ApiService.testUserId = savedTestUserId;
  }

  runApp(
    const ProviderScope(
      child: LiveSpotApp(),
    ),
  );
}
