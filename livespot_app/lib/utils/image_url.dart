import '../config/constants.dart';

/// TourAPI 이미지 CDN(`tong.visitkorea.or.kr` 등)은 CORS 헤더를 보내지 않는다.
/// 그래서 Flutter Web에서 원본 URL을 `Image.network`에 그대로 넘기면 브라우저가
/// 응답을 차단하고, 화면에는 아무 로그 없이 errorBuilder 폴백만 뜬다 —
/// API 키나 URL이 잘못된 것처럼 보이지만 실제 원인은 CORS다.
///
/// 백엔드의 `GET /api/images/proxy?url=<원본>`이 우리 서버(CORS 허용)를 거쳐
/// 이미지를 스트리밍해 주므로, 앱은 원본 대신 이 프록시 URL을 그린다.
///
/// 원본 URL을 직접 `Image.network`에 넘기는 코드를 새로 쓰지 마라. 이 헬퍼를 거친다.
String? resolveImageUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.isEmpty) return null;
  // 이미 프록시를 거친 URL을 두 번 감싸지 않는다.
  if (rawUrl.startsWith(_proxyPrefix)) return rawUrl;
  return '$_proxyPrefix${Uri.encodeComponent(rawUrl)}';
}

const String _proxyPrefix = '${AppConstants.apiBaseUrl}/images/proxy?url=';
