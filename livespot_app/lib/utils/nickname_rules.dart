/// 앱 쪽 닉네임 입력 검증 — **서버 `app/services/nickname.py`의 거울**이다.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// **최종 판정자는 서버다.** 여기 있는 것은 "뻔히 틀린 입력으로 왕복하지 않게" 하는
/// 편의일 뿐이라, 이 파일이 지켜야 할 불변식은 단 하나다:
///
///   > **서버가 허용하는 값을 앱이 먼저 거부해서는 안 된다.**
///
/// 닉네임 게이트(`nickname_setup_gate.dart`)는 **닫을 수 없는 전면 모달**이다. 앱이
/// 멀쩡한 닉네임을 거부하면 사용자는 로그아웃 말고는 앱에서 빠져나갈 길이 없다.
/// 그래서 규칙을 서버보다 조이는 것은 단순한 불편이 아니라 앱이 잠기는 사고다.
///
/// ## 정규화를 앱에서도 하는 이유 (QA 1회차 F2)
///
/// 서버는 `validate_nickname()`이 검사하기 **전에** `unicodedata.normalize("NFC", …)`로
/// 자모를 합친다(P30 ②). 앱은 이 ② 단계를 빠뜨린 채 같은 정규식·같은 길이 제한만
/// 복제했고, 그 결과 **NFD(자모 분해형) 한글이 앱에서만 거부**됐다:
///
/// ```
/// NFD "밤톨이" → 코드포인트 8개, 문자 집합 검사 실패 → 앱: 거부 / 서버: 통과(3자)
/// ```
///
/// macOS·iOS 계열의 한글 입력·붙여넣기가 실제로 NFD를 만든다. P30이 서버 정규화를
/// 넣은 이유가 바로 그것이므로 "일어날 리 없다"로 넘길 근거가 없다.
///
/// ## 왜 정규식 범위를 넓히는 대신 정규화를 택했나
///
/// 정규식에 결합 자모(U+1100~U+11FF)를 더하면 NFD 한글은 통과하지만, 합쳐지지 않는
/// **낱자 하나**(예: `ᄀ` U+1100 단독)까지 앱이 통과시키게 된다. 그 값은 서버의
/// `_ALLOWED_RE`에 없으므로 결국 400으로 튕긴다 — 판정이 또 갈린다.
/// 서버와 **같은 순서(정규화 → 검사)** 로 맞추면 두 판정이 입력 전체에 대해 일치한다.
///
/// NFC 전체 구현은 Dart 표준에 없고(`String.normalize` 없음) 새 의존성도 쓰지 않았다.
/// 대신 **한글 정준 결합만** 유니코드 표준 알고리즘(Hangul Syllable Composition,
/// UAX #15 §16)으로 구현했다 — 데이터 테이블이 필요 없는 순수 산술이고, 허용 문자
/// 집합 안에서 NFC가 실제로 바꾸는 것은 한글뿐이기 때문이다. 라틴 결합 악센트 등은
/// 합쳐지든 아니든 어차피 양쪽 다 문자 집합에서 거부한다.
/// ─────────────────────────────────────────────────────────────────────────────
library;

/// 서버 `nickname.py`의 `NICKNAME_MIN_LEN` / `NICKNAME_MAX_LEN`과 짝이다.
const int kNicknameMinLength = 2;
const int kNicknameMaxLength = 12;

/// 서버 `nickname.py`의 `ERR_LENGTH` / `ERR_CHARSET`과 **같은 문구**여야 한다.
/// 클라이언트가 문구를 새로 지어내면 "확인할 땐 이렇게 나왔는데 제출하니 다르게
/// 나온다"가 된다.
const String kNicknameLengthError = '닉네임은 2자 이상 12자 이하로 입력해 주세요';
const String kNicknameCharsetError = '닉네임에는 한글, 영문, 숫자, 밑줄(_)만 쓸 수 있어요';

/// 서버 `_ALLOWED_RE`(`^[0-9A-Za-z_가-힣ㄱ-ㅎㅏ-ㅣ]+$`)와 문자 단위로 동치다.
/// **결합 자모(U+1100~U+11FF)는 일부러 넣지 않았다** — 위 주석 참고. 정규화를 거치면
/// 정상적인 한글은 완성형(`가-힣`)이 되어 이 범위에 들어온다.
final RegExp _allowed = RegExp(r'^[가-힣ㄱ-ㅎㅏ-ㅣa-zA-Z0-9_]+$');

// 유니코드 한글 음절 결합 상수 (UAX #15). 이름은 표준 문서의 것을 그대로 쓴다.
const int _sBase = 0xAC00; // '가'
const int _lBase = 0x1100; // 초성 'ᄀ'
const int _vBase = 0x1161; // 중성 'ᅡ'
const int _tBase = 0x11A7; // 종성 시작 - 1 (tIndex 0 = 종성 없음)
const int _lCount = 19;
const int _vCount = 21;
const int _tCount = 28;
const int _nCount = _vCount * _tCount; // 588
const int _sCount = _lCount * _nCount; // 11172

/// 분해형(NFD) 한글 자모를 완성형 음절로 합친다 — 서버 NFC의 한글 부분과 같은 결과다.
///
/// L+V → LV, LV+T → LVT 두 규칙이 전부다. 합쳐지지 않는 자모는 **그대로 남겨** 뒤의
/// 문자 집합 검사가 거부하게 둔다(서버도 같다).
String composeHangul(String input) {
  final out = <int>[];
  for (final codePoint in input.runes) {
    if (out.isNotEmpty) {
      final last = out.last;

      // ① 초성 + 중성 → 받침 없는 음절
      final lIndex = last - _lBase;
      if (lIndex >= 0 && lIndex < _lCount) {
        final vIndex = codePoint - _vBase;
        if (vIndex >= 0 && vIndex < _vCount) {
          out[out.length - 1] = _sBase + (lIndex * _vCount + vIndex) * _tCount;
          continue;
        }
      }

      // ② 받침 없는 음절 + 종성 → 받침 있는 음절
      //    (`sIndex % _tCount == 0`이 "받침이 아직 없다"는 뜻이다. 이미 받침이 있는
      //     음절에 또 붙이지 않는다.)
      final sIndex = last - _sBase;
      if (sIndex >= 0 && sIndex < _sCount && sIndex % _tCount == 0) {
        final tIndex = codePoint - _tBase;
        if (tIndex > 0 && tIndex < _tCount) {
          out[out.length - 1] = last + tIndex;
          continue;
        }
      }
    }
    out.add(codePoint);
  }
  return String.fromCharCodes(out);
}

/// 저장·비교의 표준형. 서버 `normalize_nickname()`과 같은 순서다 — **trim 먼저, 결합 나중.**
String normalizeNickname(String raw) => composeHangul(raw.trim());

/// 정규화된 값 기준으로 검사한다. 에러 문구 또는 `null`(통과).
///
/// 서버 `validate_nickname()`과 판정이 갈리면 안 되므로 **길이 → 문자 집합** 순서까지
/// 같게 둔다(두 조건을 동시에 어긴 입력에 서로 다른 문구가 뜨지 않도록).
String? validateNickname(String raw) {
  final nickname = normalizeNickname(raw);

  // 정규화 후 코드포인트로 센다. 서버의 `len()`과 같은 셈법이고, 합쳐진 한글은
  // 1글자로 세어 사용자가 눈으로 센 것과도 일치한다.
  final length = nickname.runes.length;
  if (length < kNicknameMinLength || length > kNicknameMaxLength) {
    return kNicknameLengthError;
  }

  if (!_allowed.hasMatch(nickname)) return kNicknameCharsetError;

  return null;
}
