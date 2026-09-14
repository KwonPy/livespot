/// 로그인한 사용자. 백엔드 계약 1절의 `AuthUser` 그대로다.
///
/// **한 모델로 두 엔드포인트를 받는다**(계약 7절 1번):
///   - `POST /api/auth/kakao` 응답의 `user` 객체
///   - `GET  /api/auth/me` 응답 본문 전체(감싸는 키 없음)
/// 두 곳의 모양이 같으므로 [AuthUser.fromJson] 하나만 유지한다.
///
/// **식별 키는 [userId](내부 UUID)뿐이다(P4·P8·P24).** [nickname]은 사용자가 앱에서
/// 직접 정한 표시명이고 **unique**이지만(P24), 그래도 사용자 매칭·비교에 쓰지 않는다 —
/// 어떤 조회도 닉네임으로 사용자를 찾지 않는다. unique는 표시 계층의 제약일 뿐이다.
class AuthUser {
  /// 서버 내부 UUID(36자). 카카오 회원번호는 클라이언트에 내려오지 않는다(P4).
  final String userId;

  /// 사용자가 앱에서 직접 정한 닉네임(P23). **미설정이면 null이다**(P25).
  ///
  /// 카카오에서 받아오지 않는다 — 이제 카카오가 주는 값은 회원번호 하나뿐이다.
  /// null 여부를 직접 해석하지 말고 [nicknameRequired]를 볼 것(P26).
  final String? nickname;

  /// **닉네임을 아직 정하지 않았는가**(P26). 서버가 `nickname == null`로 계산해 내려준다.
  ///
  /// 앱은 이 값 하나만 본다. `nickname == null`을 앱이 따로 해석하면 판정 지점이 둘이 된다.
  /// ⚠️ `LoginResult.isNewUser`와 **다른 값이다**(P27) — 기존 사용자도 true일 수 있다
  /// (마이그레이션이 기존 카카오 사용자의 닉네임을 NULL로 밀었다).
  final bool nicknameRequired;

  /// **앞으로 항상 null이다.** 카카오 프로필 사진 동의를 받지 않기로 했다(P34·P39).
  /// 필드와 분기는 남긴다(P40) — 앱 자체 프로필 이미지 업로드가 이 자리를 그대로 쓴다.
  final String? profileImageUrl;

  final int creditBalance;
  final String trustLevel;

  /// 가입 시각. 서버가 **naive UTC**로 보낸다 — [parseServerUtc] 참고.
  final DateTime createdAt;

  const AuthUser({
    required this.userId,
    required this.nickname,
    required this.nicknameRequired,
    required this.profileImageUrl,
    required this.creditBalance,
    required this.trustLevel,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String?,
      nicknameRequired: json['nickname_required'] as bool,
      profileImageUrl: json['profile_image_url'] as String?,
      creditBalance: (json['credit_balance'] as num).toInt(),
      trustLevel: json['trust_level'] as String,
      createdAt: parseServerUtc(json['created_at'] as String),
    );
  }

  /// 서버는 타임존 표기가 없는 naive UTC를 보낸다. `Z`를 붙이지 않으면 `DateTime.parse`가
  /// 로컬 시각으로 읽어 9시간 어긋난다(`HotspotEntry._parseUtc`와 같은 규약).
  ///
  /// `LoginResult.expiresAt`도 같은 처리가 필요해 이 파일에서 공개 함수로 둔다 —
  /// 같은 규칙을 두 군데에 복사하면 한쪽만 고쳐지는 날이 온다.
  static DateTime parseServerUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}
