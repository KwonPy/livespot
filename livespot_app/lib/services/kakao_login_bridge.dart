import 'dart:async';
import 'dart:js' as js;

import '../config/constants.dart';

/// 카카오 로그인 팝업이 토큰을 주지 못한 경우. 메시지는 JS 쪽에서 온 원문이다.
///
/// **사용자 취소와 진짜 실패를 구분한다.** 팝업을 그냥 닫은 것까지 빨간 에러로 보여주면
/// 사용자는 자기가 뭔가 잘못했다고 오해한다.
class KakaoLoginException implements Exception {
  final String message;

  const KakaoLoginException(this.message);

  /// 사용자가 팝업을 닫거나 동의를 거부했을 때. 카카오는 `access_denied`(OAuth 표준)로
  /// 알려주고, SDK 버전에 따라 문구가 조금씩 다르다.
  bool get isCancelled {
    final lower = message.toLowerCase();
    return lower.contains('access_denied') ||
        lower.contains('cancel') ||
        lower.contains('user_cancelled');
  }

  @override
  String toString() => message;
}

/// `web/index.html`에 실린 카카오 JS SDK의 얇은 Dart 래퍼(Q1-B).
///
/// 지도(MapTiler)와 동일한 구조다 — 외부 SDK는 `index.html`에서 CDN으로 싣고, Dart는
/// `dart:js`로 전역 함수만 부른다. **Dart 패키지를 추가하지 않는다**(`pubspec.yaml` 무변경).
///
/// ⚠️ `dart:js`를 쓰므로 이 파일은 **웹 전용**이다. 프로젝트 전체가 이미 그렇다
/// (`map_screen.dart`가 `dart:html`/`dart:js`를 직접 쓴다, P21).
class KakaoLoginBridge {
  const KakaoLoginBridge._();

  /// 카카오 로그인 팝업을 열고 **카카오 access token**을 받아온다.
  ///
  /// 이 토큰은 우리 API의 인증 수단이 아니다(P6) — 곧바로 `POST /api/auth/kakao`로 보내
  /// 서버가 카카오에 검증한 뒤 우리 JWT로 교환한다. 앱은 이 값을 저장하지 않는다.
  static Future<String> requestAccessToken() {
    if (!AppConstants.hasKakaoJsKey) {
      // 키 미발급 상태에서 버튼을 눌러도 크래시하지 않고 원인을 말한다(계약 7절 8번).
      return Future.error(const KakaoLoginException(
        '카카오 JavaScript 키가 아직 설정되지 않았어요. '
        '--dart-define=KAKAO_JS_KEY=... 로 다시 빌드해 주세요.',
      ));
    }

    final completer = Completer<String>();

    // 콜백은 전역에 심었다가 결과를 받은 즉시 걷는다. 남겨두면 다음 로그인 시도의
    // 콜백과 겹쳐 이전 Completer가 두 번 완료되는 경로가 생긴다.
    void cleanup() {
      js.context.deleteProperty('livespotKakaoOnSuccess');
      js.context.deleteProperty('livespotKakaoOnFail');
    }

    js.context['livespotKakaoOnSuccess'] = (Object? token) {
      cleanup();
      if (completer.isCompleted) return;
      final value = token?.toString() ?? '';
      if (value.isEmpty) {
        completer.completeError(const KakaoLoginException('카카오 액세스 토큰이 비어 있어요.'));
      } else {
        completer.complete(value);
      }
    };

    js.context['livespotKakaoOnFail'] = (Object? message) {
      cleanup();
      if (completer.isCompleted) return;
      completer.completeError(KakaoLoginException(
        message?.toString().trim().isNotEmpty == true
            ? message.toString()
            : '카카오 로그인이 완료되지 않았어요.',
      ));
    };

    try {
      js.context.callMethod('livespotKakaoLogin', [AppConstants.kakaoJsKey]);
    } catch (e) {
      // index.html이 옛 버전이라 함수 자체가 없는 경우 등. 여기서 잡지 않으면
      // Completer가 영원히 완료되지 않아 로그인 버튼이 무한 로딩으로 굳는다.
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(KakaoLoginException('카카오 로그인을 시작하지 못했어요: $e'));
      }
    }

    return completer.future;
  }

  /// SDK가 들고 있는 카카오 세션을 정리한다. 로그아웃에서 우리 토큰 삭제와 함께 부른다 —
  /// 이걸 빠뜨리면 다음 로그인에서 팝업 없이 직전 계정으로 다시 붙는다.
  ///
  /// 실패해도 무시한다. 로그아웃의 본체는 우리 토큰 삭제이고, SDK 정리는 부가 작업이다.
  static void clearKakaoSession() {
    try {
      js.context.callMethod('livespotKakaoClearSession');
    } catch (_) {
      // index.html에 함수가 없는 구버전 배포 — 로그아웃 자체는 이미 끝났다.
    }
  }
}
