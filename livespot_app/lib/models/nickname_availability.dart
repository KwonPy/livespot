/// `GET /api/auth/nickname-available`의 응답(백엔드 계약 3절).
///
/// **이 값은 조언이지 확정이 아니다.** 확인과 제출 사이에 남이 같은 닉네임을 선점할 수
/// 있어서, 최종 판정은 언제나 `PUT /api/auth/me/nickname`의 409다. 이 모델을 보고
/// 제출 경로의 409 처리를 생략하면 안 된다.
class NicknameAvailability {
  /// **서버가 정규화한 결과**(앞뒤 공백 제거 + 유니코드 NFC). 앱이 보낸 문자열과 다를 수
  /// 있고, 실제로 저장·비교되는 값은 이쪽이다(P30).
  ///
  /// 예: macOS/iOS가 만드는 NFD(자모 분해형) `밤톨이_99`를 보내면 서버가 NFC로 합쳐
  /// 돌려준다 — 화면상 같지만 바이트가 다른 두 문자열이 여기서 하나로 모인다.
  final String nickname;

  final bool available;

  /// [available]이 true면 null, false면 **화면에 그대로 띄울 한국어 문구**.
  /// 앱이 사유 문구를 만들지 않는다 — 형식 위반과 중복을 서버가 같은 필드로 알려준다.
  final String? reason;

  const NicknameAvailability({
    required this.nickname,
    required this.available,
    required this.reason,
  });

  factory NicknameAvailability.fromJson(Map<String, dynamic> json) {
    return NicknameAvailability(
      nickname: json['nickname'] as String,
      available: json['available'] as bool,
      reason: json['reason'] as String?,
    );
  }
}
