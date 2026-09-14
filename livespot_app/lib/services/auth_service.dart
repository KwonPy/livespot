import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';
import '../models/login_result.dart';
import 'api_service.dart';
import 'kakao_login_bridge.dart';

/// 로그인 상태의 단일 진실 공급원(기능 9).
///
/// ─────────────────────────────────────────────────────────────────────────────
/// **이 파일은 2026-09-14에 전면 재작성됐다.** 이전 버전은 `pubspec.yaml`에 존재하지도
/// 않는 `package:firebase_auth`를 import하는 더미였고, 어디서도 import되지 않아
/// `flutter analyze` 에러로만 남아 있었다(01_spec 쟁점 E). Firebase 다리는 Q2-A로
/// 폐기됐다 — 세션은 서버가 발급한 자체 JWT + `Authorization: Bearer`다.
/// ─────────────────────────────────────────────────────────────────────────────
///
/// 상태관리는 프로젝트의 기존 패턴을 그대로 따른다 — [NotificationService]·[ApiService]와
/// 같은 **싱글턴 + [ChangeNotifier]**이고, 화면은 `ListenableBuilder`로 구독한다.
/// (Riverpod을 쓰는 화면이 `spot_detail_screen` 하나뿐이라 방식을 하나 더 늘리지 않는다.
/// 같은 이유로 이전의 `providers/auth_provider.dart`는 되살리지 않고 삭제했다.)
///
/// **토큰은 이 클래스만 저장·삭제한다.** [ApiService.accessToken]은 인터셉터가 읽는
/// 런타임 값일 뿐이고, `shared_preferences`에 쓰는 주체가 둘이 되면 로그아웃이 한쪽에만
/// 적용되는 경로가 생긴다.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// 서버 JWT 저장 키. 테스트유저 키([testUserPrefsKey])와 별개다 — 둘은 서로 다른
  /// 식별 체계이고 동시에 존재할 수 있다(Q3-A 병존).
  static const String _tokenPrefsKey = 'auth_access_token';

  /// 개발용 테스트유저 헤더의 저장 키.
  ///
  /// 2026-09-14(QA 1회차 F2): 예전에는 이 문자열의 사본이 `main.dart`와
  /// `profile_screen.dart`에 각각 있었고, **쓰는 쪽은 프로필 화면 · 읽는 쪽은 main**으로
  /// 갈려 있었다. 그래서 프로필 쪽에만 붙은 `kDebugMode` 가드가 main에는 빠졌고,
  /// "지우는 코드가 어디에도 없는" 상태가 됐다(→ 게이트 11곳이 통째로 무력화).
  /// **읽기·쓰기·삭제를 전부 이 클래스로 모은다** — 토큰과 같은 규약이다.
  static const String testUserPrefsKey = 'dev_test_user_id';

  AuthUser? _user;
  bool _restoring = false;
  String? _restoreError;

  /// 로그인한 사용자. null이면 비로그인.
  AuthUser? get user => _user;

  /// 우리 JWT로 로그인된 상태인지.
  bool get isLoggedIn => _user != null;

  /// 앱 시작 시 저장된 토큰을 확인하는 중인지(P19). 이 동안 프로필 카드는 로그인
  /// 버튼 대신 스켈레톤을 그린다 — 복원에 성공할 사용자에게 "로그인하세요"가 한 번
  /// 번쩍이는 것을 막는다.
  bool get isRestoring => _restoring;

  /// 복원이 **401이 아닌 이유**로 실패했을 때의 메시지. null이면 실패 없음.
  ///
  /// 401은 조용한 로그아웃이고(P20) 여기에 남기지 않는다. 여기에 값이 있다는 것은
  /// "토큰은 있는데 서버에 물어보지 못했다"는 뜻이라, 사용자에게 다시 시도할 기회를
  /// 줘야 한다 — 조용히 비로그인 취급하면 멀쩡한 세션이 사라진 것처럼 보인다.
  String? get restoreError => _restoreError;

  /// **서버가 나를 식별할 수 있는 상태인지.** 로그인 게이트와 알림 폴링 시작 판정이
  /// 모두 이 값을 본다.
  ///
  /// [isLoggedIn]과 다른 이유: 개발 빌드의 테스트유저 헤더(`X-Test-User-Id`)도 서버가
  /// 받아들이는 정식 식별 경로다(계약 2절 ②, TEST_MODE 한정). 이걸 빼고 [isLoggedIn]만
  /// 보면, 013~015의 다인원 QA가 쓰는 드롭다운 경로에서 제보·질문 버튼이 전부 로그인
  /// 시트에 막혀 시연이 불가능해진다.
  bool get hasServerIdentity => _user != null || ApiService.testUserId != null;

  /// 화면에 보여줄 이름. 로그인 전에는 null이고, **로그인했지만 닉네임을 아직 정하지
  /// 않았을 때도 null이다**(P25 — 미설정은 `nickname IS NULL` 하나로만 표현된다).
  String? get displayNickname => _user?.nickname;

  /// **로그인은 됐는데 앱 닉네임이 아직 없는 상태인가**(P26).
  ///
  /// 서버가 `nickname_required`로 계산해 준 값을 그대로 돌려준다 — 앱이 `nickname == null`
  /// 을 따로 해석하지 않는다. 판정 출처가 둘이 되면 016의 F2·F3(같은 사실의 출처가 둘이라
  /// 한쪽만 갱신된 버그)가 그대로 재현된다.
  ///
  /// **이 값을 보는 곳은 `app.dart`의 강제 모달 한 곳뿐이어야 한다**(P42). 화면마다
  /// `if (needsNickname)`가 늘어나기 시작하면 게이트가 흩어지고 있다는 신호다.
  ///
  /// 테스트유저 헤더([ApiService.testUserId])만 있는 개발 경로는 [_user]가 null이라 항상
  /// false다 — 의도한 결과다. 그 사용자들은 시드 단계에서 이미 닉네임을 갖고 있다.
  bool get needsNickname => _user?.nicknameRequired ?? false;

  // ── 복원 (P19) ──

  /// 저장된 토큰을 복원하고 `GET /api/auth/me`로 유효성을 확인한다.
  /// `main()`이 `runApp` 전에 한 번, 이후에는 사용자가 "다시 시도"를 누를 때 부른다.
  ///
  /// 세 갈래로 끝난다:
  ///   - 토큰 없음        → 비로그인(정상)
  ///   - 401              → **조용히** 로그아웃 + 저장된 토큰 삭제(P20, 배너 없음)
  ///   - 그 외 실패(네트워크) → 저장된 토큰은 **남기고** [restoreError]만 세운다
  ///
  /// 마지막 갈래가 중요하다. 서버가 잠깐 죽었다고 토큰을 지우면 사용자는 아무 잘못
  /// 없이 재로그인해야 한다 — 401(서버가 명시적으로 거부)만 삭제 사유다.
  Future<void> restore() async {
    _restoring = true;
    _restoreError = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenPrefsKey);
      if (token == null) {
        _user = null;
        ApiService.accessToken = null;
        return;
      }

      ApiService.accessToken = token;
      try {
        _user = await ApiService().fetchMe();
      } on UnauthorizedException {
        // 만료·위조·사용자 삭제 — 서버는 사유를 밝히지 않고 앱도 구분하지 않는다(계약 1절).
        await _forgetToken();
      } catch (e) {
        // 서버에 닿지 못했다. 로그인 상태를 "아직 모름"으로 두되 토큰은 보존한다.
        ApiService.accessToken = null;
        _user = null;
        _restoreError = e.toString().replaceFirst('Exception: ', '');
        debugPrint('[AuthService] 로그인 복원 실패(토큰은 보존): $_restoreError');
      }
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  // ── 로그인 ──

  /// 카카오 팝업 로그인(Q1-B) → 서버 검증(P6) → 우리 JWT 저장.
  ///
  /// 실패는 그대로 던진다. 사용자가 직접 누른 동작이므로 호출부(로그인 시트)가 원문을
  /// 보여준다 — 카카오 쪽 실패([KakaoLoginException])와 서버 쪽 실패(401/502)는 문구가
  /// 다르고, 특히 502를 "다시 로그인하세요"로 바꿔 보여주면 안 된다.
  Future<LoginResult> loginWithKakao() async {
    final kakaoAccessToken = await KakaoLoginBridge.requestAccessToken();
    final result = await ApiService().loginWithKakao(kakaoAccessToken);
    await _applyLogin(result);
    return result;
  }

  /// 개발/QA 전용: 카카오 없이 진짜 JWT를 발급받아 로그인한다(계약 7절 9번).
  /// 서버 TEST_MODE가 꺼져 있으면 404이므로 운영에서는 동작하지 않는다.
  Future<LoginResult> loginAsDevUser(String userId) async {
    final result = await ApiService().devLoginAs(userId);
    await _applyLogin(result);
    return result;
  }

  Future<void> _applyLogin(LoginResult result) async {
    ApiService.accessToken = result.accessToken;
    _user = result.user;
    _restoreError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefsKey, result.accessToken);
    notifyListeners();
  }

  // ── 닉네임 확정 ──

  /// 앱 닉네임을 제출하고([ApiService.updateNickname]) **응답으로 온 `AuthUser`로
  /// 현재 사용자를 통째로 교체한다.**
  ///
  /// 응답이 `/auth/me`와 같은 모양이라 재조회가 필요 없다(계약 3절). 여기서 닉네임만
  /// 복사해 넣는 대신 객체를 갈아 끼우는 이유는, `nickname_required`가 **서버가 계산한
  /// 값**이기 때문이다(P26) — 앱이 "닉네임을 넣었으니 required는 false겠지"라고 추론하는
  /// 순간 판정 지점이 하나 더 생긴다.
  ///
  /// 실패(400/409/네트워크)는 **그대로 던진다.** 호출부(닉네임 화면)가 서버 문구를 그대로
  /// 보여줘야 한다 — 특히 409("이미 사용 중인 닉네임이에요")를 삼키면 사용자는 버튼이
  /// 그냥 안 먹는 것처럼 느낀다.
  Future<AuthUser> submitNickname(String nickname) async {
    final updated = await ApiService().updateNickname(nickname);
    _user = updated;
    _restoreError = null;
    notifyListeners();
    return updated;
  }

  // ── 로그아웃 ──

  /// 로그아웃. **서버 호출이 없다**(백엔드 계약 3절) — 30일 단일 토큰이라 서버가
  /// 무효화할 수단이 없고, 200만 돌려주는 `/auth/logout`을 두면 "서버에서 세션이
  /// 끊겼다"는 오해를 부른다. 남은 대가(발급된 토큰은 만료까지 유효)는 알려진 한계다.
  ///
  /// 알림 정리([NotificationService.resetForUserSwitch], P16)와 통계 재조회(P17)는
  /// 여기서 하지 않는다 — `app.dart`가 이 [ChangeNotifier]를 구독해 한 곳에서 처리한다.
  /// 로그인·로그아웃·복원 세 경로가 같은 뒷정리를 필요로 하는데, 각 호출부가 따로
  /// 부르면 014에서 실제로 났던 "한 경로만 빠뜨리는" 버그가 그대로 재현된다.
  Future<void> logout() async {
    KakaoLoginBridge.clearKakaoSession();
    await _forgetToken();
    // 테스트유저 헤더도 함께 버린다(QA 1회차 F2-b). 이게 남으면 [hasServerIdentity]가
    // 계속 true라 `app.dart`의 `_currentIdentity`가 null이 되지 않고 → 알림 폴링·WS가
    // 로그아웃 후에도 계속 돈다(AC7 위반). "로그아웃했는데 아직 누군가로 식별되는"
    // 상태는 어느 빌드에서도 원하는 결과가 아니다.
    await setTestUserId(null);
    notifyListeners();
  }

  // ── 개발/QA: 테스트유저 헤더 전환 ──

  /// 테스트유저 헤더(`X-Test-User-Id`)를 바꾸고 **저장소까지 함께 맞춘다**.
  /// 값을 [ApiService]에 직접 대입하거나 `prefs`를 따로 쓰지 말고 반드시 이 메서드를
  /// 쓸 것 — 리스너를 깨워야 `app.dart`가 알림 계층을 다시 묶고(P16), 저장을 호출부가
  /// 따로 하면 "런타임 값은 비었는데 저장값은 남은" 상태가 생긴다(F2가 그것이다).
  ///
  /// [userId]가 `null`이면 해제다 — 저장값도 지운다.
  ///
  /// 로그인 토큰이 있으면 서버는 이 헤더를 **무시하고** 인터셉터도 보내지 않는다(계약 2절).
  /// 즉 실제 로그인 중에는 이 값을 바꿔도 아무 효과가 없다 — 그게 옳은 동작이다.
  Future<void> setTestUserId(String? userId) async {
    final changed = ApiService.testUserId != userId;
    ApiService.testUserId = userId;

    // 값이 그대로여도 저장소는 맞춰 둔다. 릴리스 빌드는 복원을 건너뛰므로
    // (`main.dart`) 런타임 값이 null인 채로 저장값만 남아 있을 수 있다.
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) {
      await prefs.remove(testUserPrefsKey);
    } else {
      await prefs.setString(testUserPrefsKey, userId);
    }

    if (changed) notifyListeners();
  }

  Future<void> _forgetToken() async {
    ApiService.accessToken = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenPrefsKey);
  }
}
