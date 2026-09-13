import 'package:dio/dio.dart';
import '../config/constants.dart';
import '../models/spot.dart';
import '../models/report.dart';
import '../models/notification_setting.dart';
import '../models/verify_location_result.dart';
import '../models/live_status.dart';
import '../models/hotspot_entry.dart';
import '../models/congestion_info.dart';
import '../models/weather.dart';
import '../models/question.dart';
import '../models/briefing.dart';
import '../models/credit_summary.dart';
import '../models/credit_ledger_entry.dart';
import '../models/activity_counts.dart';
import '../models/my_report_entry.dart';
import '../models/my_question_entry.dart';
import '../models/my_answer_entry.dart';
import '../models/bookmark_entry.dart';
import '../models/app_notification.dart';

class ApiService {
  late final Dio _dio;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  // 개발/QA 전용: 백엔드 TEST_MODE가 켜져 있을 때만 유효한 다중 테스트유저 전환용 헤더.
  // 프로필 화면의 테스트유저 드롭다운에서 설정한다. 운영 빌드에서는 null로 유지하면 된다.
  static String? testUserId;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      // 백엔드가 이제 8초 내로 실패를 반환하므로 그보다 살짝 여유를 둔다.
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
    ));

    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (testUserId != null) {
        options.headers['X-Test-User-Id'] = testUserId;
      }
      handler.next(options);
    }));

    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
    ));
  }

  Future<List<Spot>> fetchSpots() async {
    try {
      final response = await _dio.get('/spots/all', queryParameters: {'num_of_rows': 20});
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Spot.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch spots: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch spots: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchSpotDetail(String contentId) async {
    try {
      final response = await _dio.get('/spots/$contentId');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      print('Error fetching spot detail: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchSpotIntro(String contentId, String contentTypeId) async {
    try {
      final response = await _dio.get('/spots/$contentId/intro', queryParameters: {
        'content_type_id': contentTypeId,
      });
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      print('Error fetching spot intro: $e');
    }
    return null;
  }

  /// 주변 관광지를 조회합니다. 서버에 연결할 수 없거나 요청이 실패하면
  /// (결과가 0개인 경우와 구분할 수 있도록) 예외를 던집니다.
  Future<List<Spot>> fetchNearbySpots(double lat, double lng, {int radius = 5000}) async {
    final response = await _dio.post('/spots/nearby', data: {
      'lat': lat,
      'lng': lng,
      'radius': radius,
    });
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => Spot.fromJson(json)).toList();
    }
    throw Exception('Failed to fetch nearby spots: ${response.statusCode}');
  }

  /// 키워드로 관광지를 직접 검색합니다 (TourAPI searchKeyword2).
  /// 지도 탭 검색에 사용 — nearby와 동일하게 서버에서 지역/카테고리 필터가 적용된 결과가 온다.
  Future<List<Spot>> searchSpots(String keyword) async {
    final response = await _dio.get('/spots', queryParameters: {
      'keyword': keyword,
    });
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => Spot.fromJson(json)).toList();
    }
    throw Exception('Failed to search spots: ${response.statusCode}');
  }

  /// 현장 제보를 등록합니다. GPS 인증 범위를 벗어나거나 입력값이 잘못되면
  /// 서버가 4xx를 돌려주는데, 그 메시지를 그대로 담아 예외를 던집니다.
  Future<Report> submitReport({
    required String spotContentId,
    required String crowdednessLevel,
    required String waitingTime,
    String? parkingStatus,
    String? comment,
    required double lat,
    required double lng,
    required String clientRequestId,
  }) async {
    try {
      final response = await _dio.post('/reports', data: {
        'spot_content_id': spotContentId,
        'crowdedness_level': crowdednessLevel,
        'waiting_time': waitingTime,
        'parking_status': parkingStatus,
        'comment': comment,
        'lat': lat,
        'lng': lng,
        'client_request_id': clientRequestId,
      });
      return Report.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  Future<List<Report>> fetchReports(String spotContentId) async {
    final response = await _dio.get('/reports', queryParameters: {
      'spot_content_id': spotContentId,
    });
    final List<dynamic> data = response.data;
    return data.map((json) => Report.fromJson(json)).toList();
  }

  /// 기능 5(LIVE 상태창). 매번 실시간 계산된 값 — 방금 올린 제보가 바로 반영된다.
  Future<LiveStatus> fetchLiveStatus(String contentId) async {
    final response = await _dio.get('/live/status/$contentId');
    return LiveStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// 실시간 핫스팟 랭킹 — 실제 제보 활동이 있는 관광지만 대상.
  Future<List<HotspotEntry>> fetchHotspots({int limit = 5}) async {
    final response = await _dio.get('/live/hotspots', queryParameters: {'limit': limit});
    final List<dynamic> data = response.data;
    return data.map((json) => HotspotEntry.fromJson(json)).toList();
  }

  /// 기능 9. 방문 집중률 "예측" 단건 조회 (한국관광공사, 상세페이지용).
  Future<CongestionInfo> fetchCongestion(String contentId) async {
    final response = await _dio.get('/spots/$contentId/congestion');
    return CongestionInfo.fromJson(response.data as Map<String, dynamic>);
  }

  /// 관광지 실시간 날씨 (Open-Meteo). 좌표는 보내지 않는다 — 서버가 content_id로
  /// 좌표를 자체 조회한다(HOT SPOTS 진입처럼 Spot.latitude가 null인 경우 대응).
  ///
  /// 날씨 조회 실패는 200 + available:false로 오므로 여기서 예외가 되지 않는다.
  /// 예외로 올라오는 건 관광지 자체가 없거나(404) 네트워크가 죽은 경우뿐이다.
  Future<WeatherInfo> fetchWeather(String contentId) async {
    final response = await _dio.get('/spots/$contentId/weather');
    return WeatherInfo.fromJson(response.data as Map<String, dynamic>);
  }

  /// 기능 10. AI 브리핑 단건 조회 (인증 불필요).
  ///
  /// 서버는 관광지가 없을 때(404)를 빼면 **항상 200**을 준다 — Gemini 키 오류·타임아웃·
  /// 재료 부족까지 전부 200 + source(TEMPLATE/NONE)로 표현된다. 그래서 여기서 예외가
  /// 올라오는 건 관광지가 없거나 네트워크가 죽은 경우뿐이고, 화면은 그때 섹션을 숨긴다.
  ///
  /// 캐시 미스 시 Gemini 생성까지 수 초가 걸릴 수 있다(서버 타임아웃 내에서 폴백).
  Future<Briefing> fetchBriefing(String contentId) async {
    final response = await _dio.get('/spots/$contentId/briefing');
    return Briefing.fromJson(response.data as Map<String, dynamic>);
  }

  /// 기능 9. 지도 마커용 — 화면에 보이는 관광지들의 집중률 예측을 한 번에 조회한다.
  ///
  /// 집중률 API는 content_id를 모르고 관광지명으로만 데이터를 구분하므로 title·address를
  /// 함께 보낸다. 시군구 판별과 이름 매칭은 전부 서버가 하고, 결과는 content_id 기준
  /// Map으로 돌아온다. 데이터가 없는 관광지도 level:'unknown'으로 항상 채워져서 온다.
  Future<Map<String, CongestionInfo>> fetchCongestionBatch(List<Spot> spots) async {
    if (spots.isEmpty) return {};
    final response = await _dio.post('/spots/congestion-batch', data: {
      'spots': spots
          .map((s) => {
                'content_id': s.contentId,
                'title': s.title,
                'address': s.address,
              })
          .toList(),
    });
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return data.map((k, v) => MapEntry(k, CongestionInfo.fromJson(v as Map<String, dynamic>)));
  }

  /// 관광지별 자동 제보 유도 알림 설정을 조회합니다. enabledOnly=true면 켜져있는 것만.
  Future<List<NotificationSetting>> fetchNotificationSettings({bool enabledOnly = false}) async {
    final response = await _dio.get('/notifications/settings', queryParameters: {
      'enabled_only': enabledOnly,
    });
    final List<dynamic> data = response.data;
    return data.map((json) => NotificationSetting.fromJson(json)).toList();
  }

  Future<NotificationSetting> fetchNotificationSetting(String contentId) async {
    final response = await _dio.get('/notifications/settings/$contentId');
    return NotificationSetting.fromJson(response.data as Map<String, dynamic>);
  }

  Future<NotificationSetting> setNotificationSetting(String contentId, bool pushEnabled) async {
    final response = await _dio.post('/notifications/settings', data: {
      'content_id': contentId,
      'push_enabled': pushEnabled,
    });
    return NotificationSetting.fromJson(response.data as Map<String, dynamic>);
  }

  /// 기능 4(능동적 현장 인증). 자동 알림 설정과 무관하게, 사용자가 직접 고른
  /// spotContentId 기준으로만 현재 위치와의 거리를 검증합니다.
  Future<VerifyLocationResult> verifyLocation(String contentId, double lat, double lng) async {
    final response = await _dio.post('/reports/verify-location', data: {
      'content_id': contentId,
      'lat': lat,
      'lng': lng,
    });
    return VerifyLocationResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// 기능 7(현장 Q&A). 질문 등록 — 위치 제한 없음(질문자는 원래 멀리 있는 사람).
  Future<Question> submitQuestion({
    required String spotContentId,
    required String content,
  }) async {
    try {
      final response = await _dio.post('/questions', data: {
        'spot_content_id': spotContentId,
        'content': content,
      });
      return Question.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  /// 관광지의 오늘(KST) 현장 Q&A 목록 — 답변까지 함께 내려온다.
  /// pendingOnly=true면 아직 답변이 없고 만료되지 않은 질문만, activeOnly=true면 만료된
  /// 질문을 제외한다(Live 페이지 "내 현장 Q&A"용 — 상세페이지는 기본값으로 만료도 보여준다).
  Future<List<Question>> fetchQuestions(
    String spotContentId, {
    bool pendingOnly = false,
    bool activeOnly = false,
  }) async {
    final response = await _dio.get('/questions', queryParameters: {
      'spot_content_id': spotContentId,
      'pending_only': pendingOnly,
      'active_only': activeOnly,
    });
    final List<dynamic> data = response.data;
    return data.map((json) => Question.fromJson(json)).toList();
  }

  /// Live 페이지의 "전체 LIVE Q&A" — 관광지 구분 없이 오늘(KST) 등록된 활성 질문 중 최신순.
  /// 이 목록에서는 누구도 답변할 수 없다(정책) — 조회 전용.
  Future<List<Question>> fetchRecentQuestions({int limit = 10}) async {
    final response = await _dio.get('/questions/recent', queryParameters: {'limit': limit});
    final List<dynamic> data = response.data;
    return data.map((json) => Question.fromJson(json)).toList();
  }

  /// 답변 등록. GPS 현장 인증(기능 3)이 되어야만 저장된다 — 서버가 매번 거리를 다시
  /// 계산해 판정하므로, 인증 범위를 벗어나면 403과 함께 예외가 던져진다.
  Future<Answer> submitAnswer({
    required String questionId,
    required String content,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await _dio.post('/questions/$questionId/answers', data: {
        'content': content,
        'lat': lat,
        'lng': lng,
      });
      return Answer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  // ---------------------------------------------------------------------------
  // 기능 4(Credit) · 11(뱃지)
  //
  // 세 엔드포인트 모두 `me` = deps.get_current_user_id()가 돌려주는 사용자다(P24).
  // 지금은 test_user 고정이고, 테스트유저 드롭다운이 보내는 X-Test-User-Id 헤더
  // (위 인터셉터)로 전환된다. 로그인이 붙으면 서버의 그 함수만 바뀐다.
  //
  // 서버는 원장이 비어 있어도 200 + 기본값을 준다(P23). 따라서 여기서 예외가
  // 올라오는 건 **서버가 죽었거나 응답 형태가 계약과 다른 경우뿐**이고,
  // 화면은 그것을 "0건"이 아니라 에러로 보여줘야 한다.
  // ---------------------------------------------------------------------------

  /// 내 크레딧 잔액·누적·뱃지. 뱃지 등급 판정은 전부 서버가 한다(P22).
  Future<CreditSummary> fetchMyCredit() async {
    final response = await _dio.get('/credits/me');
    if (response.statusCode == 200) {
      return CreditSummary.fromJson(response.data as Map<String, dynamic>);
    }
    throw Exception('Failed to fetch credit summary: ${response.statusCode}');
  }

  /// 크레딧 원장 내역(최신순). 적립이 하나도 없으면 **빈 리스트**가 온다 —
  /// 실패와 구분되도록 실패는 반드시 예외로 던진다.
  Future<List<CreditLedgerEntry>> fetchMyLedger({int? limit}) async {
    final response = await _dio.get(
      '/credits/me/ledger',
      queryParameters: limit == null ? null : {'limit': limit},
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => CreditLedgerEntry.fromJson(json as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to fetch credit ledger: ${response.statusCode}');
  }

  /// 내 활동 건수(제보/답변/질문). 크레딧과 별도 집계다.
  Future<ActivityCounts> fetchMyActivity() async {
    final response = await _dio.get('/credits/me/activity');
    if (response.statusCode == 200) {
      return ActivityCounts.fromJson(response.data as Map<String, dynamic>);
    }
    throw Exception('Failed to fetch activity counts: ${response.statusCode}');
  }

  /// 마이 화면 "내 제보" 목록(기능 12). 최신순, 관광지 이름이 조인되어 온다.
  Future<List<MyReportEntry>> fetchMyReports() async {
    final response = await _dio.get('/reports/me');
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => MyReportEntry.fromJson(json as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to fetch my reports: ${response.statusCode}');
  }

  /// 마이 화면 "내 Q&A" 중 내가 쓴 질문 목록(기능 12). 각 질문에 달린 답변까지 포함된다.
  Future<List<MyQuestionEntry>> fetchMyQuestions() async {
    final response = await _dio.get('/questions/me');
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => MyQuestionEntry.fromJson(json as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to fetch my questions: ${response.statusCode}');
  }

  /// 마이 화면 "내 Q&A" 중 내가 단 답변 목록(기능 12). 원 질문 내용이 함께 조인되어 온다.
  Future<List<MyAnswerEntry>> fetchMyAnswers() async {
    final response = await _dio.get('/questions/me/answers');
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => MyAnswerEntry.fromJson(json as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to fetch my answers: ${response.statusCode}');
  }

  // ── 북마크(기능 12) ──
  //
  // 단건 상태 조회 엔드포인트는 없다. 상세페이지도 이 목록을 받아 content_id 포함
  // 여부로 판정한다(정책 P-B11) — 목록 규모가 수십 건이라 전용 API를 만들 근거가 없다.

  /// 내 북마크 목록(최신순). 하나도 없으면 **빈 리스트**가 온다 —
  /// 실패와 구분되도록 실패는 반드시 예외로 던진다(fetchMyReports와 같은 규약).
  Future<List<BookmarkEntry>> fetchBookmarks() async {
    final response = await _dio.get('/bookmarks');
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => BookmarkEntry.fromJson(json as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to fetch bookmarks: ${response.statusCode}');
  }

  /// 북마크 추가. 서버가 멱등이라 이미 담긴 관광지를 다시 눌러도 200이 온다.
  Future<void> addBookmark(String contentId) async {
    final response = await _dio.post('/bookmarks', data: {'content_id': contentId});
    if (response.statusCode != 200) {
      throw Exception('Failed to add bookmark: ${response.statusCode}');
    }
  }

  /// 북마크 해제. 서버가 멱등이라 없는 북마크를 지워도 200이 온다.
  Future<void> removeBookmark(String contentId) async {
    final response = await _dio.delete('/bookmarks/$contentId');
    if (response.statusCode != 200) {
      throw Exception('Failed to remove bookmark: ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // 기능 8(질문/답변 알림)
  //
  // ⚠️ 위쪽의 fetchNotificationSettings / setNotificationSetting(`/notifications/settings`)은
  //    기능 3의 **관광지별** 자동 제보 유도 알림 설정(기본 꺼짐)이다. 아래 push-settings는
  //    기능 8의 **전역** 스위치(기본 켜짐)로 완전히 다른 API다 — 경로가 비슷하다고 섞지 말 것.
  //
  // 서버는 조회 실패를 정직하게 500으로 던진다(빈 배열 폴백 없음, P11). 여기서도
  // 그대로 예외로 전파한다 — "알림 0건"과 "못 읽었음"을 화면이 구분할 수 있어야 한다.
  // 그 예외를 사용자에게 보여줄지는 호출부가 정한다: 배경 폴링은 조용히 삼키고(P12),
  // 사용자가 직접 누른 동작은 메시지를 그대로 보여준다.
  // ---------------------------------------------------------------------------

  /// 내 알림 목록 + 미읽음 수. 만료 판정은 서버가 한다 — 연결된 질문이 유효시간
  /// 2시간을 넘겼으면(P22·P24) 목록에서 빠진 채로 온다. 앱은 다시 계산하지 않는다.
  /// [limit]은 서버에서 1~100만 허용되며, 벗어나면 422다 — 앱이 범위 밖 값을 보내지 않는다.
  Future<NotificationList> fetchNotifications({int? limit}) async {
    try {
      final response = await _dio.get(
        '/notifications',
        queryParameters: limit == null ? null : {'limit': limit},
      );
      return NotificationList.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  /// 알림 1건 읽음 처리. 멱등이라 이미 읽은 알림을 다시 호출해도 200 + updated_count 0.
  /// 없는 id이거나 남의 알림이면 404 + detail 문자열이 온다.
  Future<NotificationReadResult> markNotificationRead(String notificationId) async {
    try {
      final response = await _dio.post('/notifications/$notificationId/read');
      return NotificationReadResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  /// 미읽음 알림을 한 번에 읽음 처리. 미읽음이 0건이어도 200이다.
  Future<NotificationReadResult> markAllNotificationsRead() async {
    try {
      final response = await _dio.post('/notifications/read-all');
      return NotificationReadResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  // 2026-09-13(015) 전역 알림 ON/OFF 토글 폐기로 `fetchPushSettings`/`updatePushSettings`
  // (`/notifications/push-settings` 2종)를 제거했다. 알림은 이제 항상 켜져 있다.
  //
  // ⚠️ 바로 위·아래에 있는 `/notifications/settings` 3종(관광지별 제보 유도 알림, 기능 3)은
  // 이름만 비슷한 **다른 기능**이라 그대로 둔다. 혼동해서 지우면 상세페이지 종 아이콘이 죽는다.

  /// 개발용: TEST_MODE가 꺼져있으면(운영) 서버가 404를 준다 — 그 경우 빈 목록으로 처리.
  Future<List<Map<String, dynamic>>> fetchTestUsers() async {
    try {
      final response = await _dio.get('/dev/test-users');
      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException {
      return [];
    }
  }

  String _extractErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (data is Map && data['detail'] is List) {
      final msgs = (data['detail'] as List)
          .map((d) => d is Map ? (d['msg'] ?? d.toString()) : d.toString())
          .join(', ');
      return msgs;
    }
    return e.message ?? '알 수 없는 오류가 발생했습니다';
  }
}
