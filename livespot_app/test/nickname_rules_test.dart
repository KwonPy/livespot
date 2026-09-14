import 'package:flutter_test/flutter_test.dart';
import 'package:livespot_app/utils/nickname_rules.dart';

/// 앱의 닉네임 검증이 서버(`app/services/nickname.py`)보다 **조이지 않는지** 지킨다.
///
/// 이 파일이 있는 이유는 한 가지다: 닉네임 게이트는 닫을 수 없는 전면 모달이라,
/// 서버가 허용하는 값을 앱이 거부하면 사용자가 앱에 갇힌다. 그 회귀는 화면을 띄워
/// 눈으로 보기 전에는 드러나지 않으므로 여기서 잡는다.
///
/// NFD 문자열은 **코드포인트로 직접 조립한다.** 소스 파일에 분해형 한글을 그대로
/// 적으면 에디터·git·포매터 중 무엇이든 저장 과정에서 NFC로 합쳐 버릴 수 있고,
/// 그러면 테스트가 조용히 아무것도 검증하지 않게 된다.
String _nfd(List<int> codePoints) => String.fromCharCodes(codePoints);

void main() {
  // "밤톨이" 분해형 — QA 1회차 F2의 실측 반례(runes.length=8, 기존 정규식 통과 실패)
  final nfdBamtori = _nfd([0x1107, 0x1161, 0x11B7, 0x1110, 0x1169, 0x11AF, 0x110B, 0x1175]);
  // "여행하는밤" 분해형 — 같은 리포트의 두 번째 반례(runes.length=13 → 길이 초과로 거부됐다)
  final nfdYeohaeng = _nfd([
    0x110B, 0x1167, // 여
    0x1112, 0x1162, 0x11BC, // 행
    0x1112, 0x1161, // 하
    0x1102, 0x1173, 0x11AB, // 는
    0x1107, 0x1161, 0x11B7, // 밤
  ]);

  group('composeHangul / normalizeNickname', () {
    test('분해형 한글이 완성형과 같은 문자열로 합쳐진다', () {
      expect(nfdBamtori.runes.length, 8); // 전제 확인: 정말 분해형인가
      expect(composeHangul(nfdBamtori), '밤톨이');
      expect(composeHangul(nfdYeohaeng), '여행하는밤');
    });

    test('받침 없는 음절도, 이미 완성형인 글자도 그대로 유지된다', () {
      expect(composeHangul(_nfd([0x1112, 0x1161])), '하');
      expect(composeHangul('여행하는밤톨_1'), '여행하는밤톨_1');
    });

    test('합쳐지지 않는 낱자는 남긴다 — 서버도 이것을 거부한다', () {
      // 초성만 둘. NFC도 합치지 않으므로 여기서 임의로 통과시키면 서버와 판정이 갈린다.
      expect(composeHangul(_nfd([0x1100, 0x1100])).runes.length, 2);
      expect(validateNickname(_nfd([0x1100, 0x1100])), kNicknameCharsetError);
    });

    test('앞뒤 공백을 먼저 제거한다 (서버 strip → NFC 순서와 동일)', () {
      expect(normalizeNickname('  큐에이닉_77  '), '큐에이닉_77');
    });
  });

  group('validateNickname — 서버가 허용하는 것을 거부하지 않는다', () {
    test('분해형 한글 닉네임을 통과시킨다 (F2 회귀)', () {
      expect(validateNickname(nfdBamtori), isNull);
      expect(validateNickname(nfdYeohaeng), isNull);
    });

    test('길이를 정규화 후 코드포인트로 센다 — 분해형이라고 초과가 되지 않는다', () {
      // 12자(완성형 기준)를 분해형으로 넣어도 통과해야 한다.
      // "하"(초성 ᄒ + 중성 ᅡ) × 12 = 24 코드포인트
      final twelve = List<int>.generate(24, (i) => i.isEven ? 0x1112 : 0x1161);
      expect(_nfd(twelve).runes.length, 24);
      expect(validateNickname(_nfd(twelve)), isNull);
    });

    test('완성형·호환 자모·영문·숫자·밑줄이 모두 통과한다', () {
      expect(validateNickname('밤톨이'), isNull);
      expect(validateNickname('ㅋㅋ'), isNull); // 호환 자모 — 서버가 명시적으로 허용한다
      expect(validateNickname('traveler_01'), isNull);
      expect(validateNickname('큐에이닉_77'), isNull);
    });
  });

  group('validateNickname — 서버와 같은 문구로 거부한다', () {
    test('2자 미만 / 12자 초과는 길이 문구', () {
      expect(validateNickname('밤'), kNicknameLengthError);
      expect(validateNickname('가' * 13), kNicknameLengthError);
      expect(validateNickname('   '), kNicknameLengthError); // trim 후 0자
    });

    test('공백·이모지·특수문자는 문자 집합 문구', () {
      expect(validateNickname('여 행자'), kNicknameCharsetError);
      expect(validateNickname('여행자😀'), kNicknameCharsetError);
      expect(validateNickname('hello!'), kNicknameCharsetError);
    });

    test('길이와 문자 집합을 동시에 어기면 길이 문구가 먼저다 (서버와 같은 순서)', () {
      expect(validateNickname('!'), kNicknameLengthError);
    });
  });
}
