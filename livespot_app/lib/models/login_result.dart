import 'auth_user.dart';

/// 로그인 응답. 백엔드 계약 1절의 `LoginResponse`.
///
/// `POST /api/auth/kakao`와 `POST /api/dev/login-as/{user_id}`가 **완전히 같은 모양**을
/// 돌려준다(계약 1절) — 개발용 경로라고 다른 모델을 만들지 않는다.
class LoginResult {
  final String accessToken;

  /// 항상 `"Bearer"`. 헤더를 조립할 때 문자열을 하드코딩하지 않으려고 받아둔다.
  final String tokenType;

  /// 토큰 만료 시각(naive UTC). 현재는 화면에 쓰지 않지만, 앱이 만료를 **판정**하지는
  /// 않는다 — 만료 판정은 서버가 401로 알려주고 앱은 그때 조용히 로그아웃한다(P20).
  final DateTime expiresAt;

  /// 이번 호출로 users 행이 새로 생겼는지. 가입/로그인이 같은 경로라서(P7) 이 값으로만
  /// 구분된다 — 첫 로그인 환영 문구에 쓴다.
  final bool isNewUser;

  final AuthUser user;

  const LoginResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.isNewUser,
    required this.user,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresAt: AuthUser.parseServerUtc(json['expires_at'] as String),
      isNewUser: json['is_new_user'] as bool,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
