import 'package:shared_preferences/shared_preferences.dart';
import '../models/credit_summary.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// 뱃지 승급 감지.
///
/// 제보·답변 응답에는 크레딧 적립 여부가 드러나지 않는다(`profile_screen.dart`의
/// "백엔드 계약 4절" 주석과 같은 제약). 그래서 성공 직후 `/credits/me`를 다시 불러
/// 마지막으로 봤던 뱃지 코드와 비교하는 방식으로 "방금 등급이 올랐는지"를 판단한다.
class BadgeTracker {
  static const _prefsKeyPrefix = 'last_seen_badge_code';

  /// 사람마다 등급이 다르므로 키를 **사용자별로** 분리한다.
  ///
  /// 신원 판정 순서는 `app.dart`의 `_currentIdentity`·서버 `deps.py`와 같다 —
  /// ①로그인 `user_id` ②테스트유저 헤더. 기능 9 전에는 ②밖에 없어서, 카카오로
  /// 로그인한 사용자가 전부 `…:default` 한 칸을 공유했다(QA 1회차 F3): 계정 A로 쓰다
  /// B로 로그인하면 B가 원래 갖고 있던 등급을 "방금 승급"으로 축하하거나, 반대로
  /// B의 진짜 승급이 조용히 넘어갔다.
  ///
  /// 호출 시점마다 계산하므로 사용자 전환에 별도 초기화 훅이 필요 없다 —
  /// [BadgeTracker]는 메모리 상태를 들고 있지 않고, 기준값은 전부 이 키 아래에 있다.
  /// (`NotificationService.resetForUserSwitch`가 하는 일이 여기서는 필요 없는 이유다.)
  static String _prefsKey() =>
      '$_prefsKeyPrefix:${AuthService().user?.userId ?? ApiService.testUserId ?? 'anonymous'}';

  /// 방금 승급했으면 새 [CreditBadge]를, 아니면(첫 조회 포함) `null`을 돌려준다.
  ///
  /// 실패는 조용히 삼킨다 — 이 확인은 축하 팝업을 위한 부가 기능일 뿐이라,
  /// 실패했다고 제보·답변 자체의 성공 흐름(SnackBar → 화면 닫기)을 막으면 안 된다.
  static Future<CreditBadge?> checkForLevelUp() async {
    try {
      final summary = await ApiService().fetchMyCredit();
      final prefs = await SharedPreferences.getInstance();
      final key = _prefsKey();
      final lastCode = prefs.getString(key);
      await prefs.setString(key, summary.badge.code);

      // lastCode가 없으면 이 기기에서 처음 확인하는 것이다 — 원래 있던 등급까지
      // "방금 딴 것"처럼 축하하면 안 되므로 팝업 없이 기준값만 저장한다.
      if (lastCode == null || lastCode == summary.badge.code) return null;
      return summary.badge;
    } catch (_) {
      return null;
    }
  }
}
