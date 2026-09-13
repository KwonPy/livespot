import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';
import '../models/app_notification.dart';
import 'api_service.dart';

/// 기능 8(질문/답변 알림)의 인앱 전달 계층.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// **2026-09-12부터 전달 경로가 WebSocket + 폴링 폴백으로 바뀌었다.**
///
/// 기본 경로는 `GET /api/notifications/ws`에 연결해 두고, 서버가 새 알림이 생겼을 때
/// 보내는 빈 신호(`{"type":"notification"}`)를 받으면 그 즉시 [refresh]를 부르는 것이다.
/// **신호에는 알림 내용이 없다** — 여전히 `GET /api/notifications`(HTTP)가 유일한 진실
/// 공급원이고, WS는 "폴링 주기를 기다리지 않게 깨우는 역할"만 한다. 그래서 서버가 계산하는
/// 것(만료 판정 등)을 앱이 다시 계산하지 않는다는 원칙이 그대로 유지된다.
///
/// WS가 연결돼 있는 동안은 기존의 주기적 `Timer`([_pollTimer])를 **멈춘다** — 깨움 신호가
/// 그 역할을 대신한다. WS가 끊기면(네트워크 문제, 서버 재시작, 프록시 타임아웃 등) 즉시
/// 폴백 폴링을 재개하고, 동시에 WS 재연결을 계속 시도한다. 재연결에 성공하면 다시 폴백
/// 폴링을 멈춘다 — 이 상태 전환이 [_onWsConnected]/[_onWsDisconnected]다.
///
/// 이 이원화가 안전한 이유: 화면(배너·목록·배지)은 전부 [items]/[unreadCount]만 보고
/// 그리므로, 알림이 WS로 왔는지 폴링으로 왔는지 위젯 코드는 구분할 필요가 없다.
///
/// ⚠️ **Android 이식 시 교체 지점.** 서버 쪽에서 실제 Web Push/FCM을 붙일 때도 이 파일
/// 하나만 바뀌면 된다 — [_connectWebSocket]의 연결 대상을 바꾸거나, 푸시 수신 콜백으로
/// [refresh]를 부르는 것으로 교체하면 된다. 서버 쪽 대응 지점은 `services/notification.py`의
/// `NotificationSender` 구현체 하나다(P14).
/// ─────────────────────────────────────────────────────────────────────────────
///
/// 상태관리는 프로젝트의 기존 패턴을 따른다 — [ApiService]·`LocationService`·
/// `ProximityAlertService`와 같은 **싱글턴 서비스**이고, 위젯은 [ChangeNotifier]를
/// `ListenableBuilder`로 구독한다. (Riverpod 의존성이 있긴 하지만 실제로 쓰는 화면이
/// `spot_detail_screen` 하나뿐이라, 새 기능 때문에 상태관리 방식을 하나 더 늘리지 않는다.)
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final ApiService _api = ApiService();

  // ── 화면이 읽는 상태 ──
  List<NotificationEntry> _items = const [];
  int _unreadCount = 0;

  /// 만료되지 않은 알림, 최신순. 서버가 정렬해 준 순서를 그대로 유지한다.
  List<NotificationEntry> get items => _items;

  /// 미읽음 수(만료 제외). MyPage 배지가 이 값을 그린다.
  int get unreadCount => _unreadCount;

  // 알림 수명을 전역 값으로 들고 있던 _ttlMinutes는 2026-09-10 방향 수정(P24)으로
  // 제거했다. 만료 기준이 "알림 생성 후 30분"에서 "연결된 질문의 2시간 유효시간"으로
  // 바뀌면서 알림마다 만료 시각이 달라졌고, 서버도 ttl_minutes를 더 이상 보내지 않는다.
  // 남은 시간이 필요하면 항목의 NotificationEntry.expiresAt을 쓴다.

  /// 지금 배너로 띄워야 할 알림. 없으면 null.
  NotificationEntry? get bannerEntry => _bannerEntry;
  NotificationEntry? _bannerEntry;

  /// 재접속(이 세션의 첫 관측) 시 이미 쌓여 있던 미읽음 개수. 없으면(또는 아직 처리 전이
  /// 아니면) null. 실시간 배너([bannerEntry])와 별개의 슬롯이다 — 실시간은 "무엇이 왔는지"
  /// 하나를 구체적으로 보여주고, 이건 "당신이 없는 동안 얼마나 쌓였는지"를 요약해 보여준다.
  ///
  /// 2026-09-12 사용자 정책: "사용자를 귀찮게 해야 참여율이 올라간다 — 최대한 노출해야
  /// 한다"(9절 원문 참조). 그래서 기존에는 "묵은 알림은 배너 없이 배지로만" 이었던 첫
  /// 관측을, 밀린 알림이 있으면 요약 다이얼로그로 알리도록 뒤집었다. 다이얼로그 하나로
  /// 묶는 이유(개별 알림마다 띄우지 않는 이유)는 대량일 때 사용자가 계속 다이얼로그를
  /// 닫아야 하는 번거로움을 피하기 위해서다(사용자 확인).
  int? get backlogUnreadCount => _backlogUnreadCount;
  int? _backlogUnreadCount;

  /// 폴링이 한 번이라도 성공했는지. 목록 화면이 "아직 못 읽음"과 "0건"을 구분하는 데 쓴다.
  bool get hasLoadedOnce => _lastObservedUnreadIds != null;

  // ── 배너 판정용 ──
  //
  // 직전 폴링에서 관측한 미읽음 id 집합. **메모리에만 둔다**(기기 로컬 저장 없음) —
  // "이미 본 알림"의 진짜 기준은 서버의 read_at이고, 이 값은 "이번 폴링에서 새로
  // 나타난 id가 있나"만 판정한다.
  //
  // 예전에는 **개수**만 비교했다. 그러면 같은 폴링 주기 안에서 알림 1건이 질문 만료로
  // 목록에서 빠지고 다른 1건이 새로 도착하면 개수가 그대로라 배너가 안 뜨는 구멍이
  // 있었다 — id 집합으로 바꿔 "무엇이 새로 왔는가"를 직접 물어본다.
  //
  // null = 아직 한 번도 관측하지 않음. 이때는 [backlogUnreadCount] 요약만 세운다(있으면).
  // resetForUserSwitch()는 이 값을 null이 아니라 **빈 집합**으로 세운다 — "다른 사람으로
  // 로그인" 취급이라 실시간 배너([_bannerEntry]) 경로를 타야지, 재접속 요약 경로를 다시
  // 타면 안 되기 때문이다(계정 전환마다 "쌓인 알림 N건" 다이얼로그가 뜨는 건 과하다).
  Set<String>? _lastObservedUnreadIds;

  Timer? _pollTimer;

  // WebSocket 연결. null이면 "지금 연결 시도 중이 아니거나 끊긴 상태" — 이때는
  // _pollTimer가 폴백으로 돈다.
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _wsReconnectTimer;
  bool _stopped = true; // stop() 이후 재연결 타이머가 계속 도는 것을 막는다.

  // 이미 나가 있는 조회. 느린 네트워크에서 요청이 겹쳐 쌓이는 것을 막는다.
  //
  // **건너뛰지 않고 같은 Future를 돌려주는 이유:** 목록 화면이 부른 refresh를 "이미
  // 폴링 중"이라며 즉시 성공으로 끝내면, 그 폴링이 실패했을 때 화면은 에러를 못 보고
  // 빈 목록을 그린다 — 실패가 "알림 없음"으로 둔갑하는 바로 그 패턴이다.
  Future<void>? _inFlight;

  /// 전역 전달 시작. 앱 셸(`app.dart`)이 한 번만 부른다. 이미 돌고 있으면 아무 일도
  /// 하지 않는다(중복 시작 방지).
  ///
  /// WS 연결을 시도하는 **동시에** 폴백 폴링도 바로 켠다 — WS 핸드셰이크가 끝나기 전
  /// 구간을 비워두지 않기 위해서다. WS가 붙으면 [_onWsConnected]가 폴백을 끈다.
  void start() {
    if (!_stopped) return;
    _stopped = false;
    _startPollTimer();
    _connectWebSocket();
  }

  /// 타이머·연결 정리. **웹에서 타이머 누수는 아무 증상 없이 조용히 쌓인다** —
  /// 셸의 dispose에서 반드시 부를 것.
  void stop() {
    _stopped = true;
    _stopPollTimer();
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    _closeWebSocket();
  }

  void _startPollTimer() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(
      const Duration(seconds: AppConstants.notificationPollIntervalSeconds),
      (_) => _poll(),
    );
    _poll(); // 첫 조회는 기다리지 않는다(기준선 세우기 + 배지 초기화)
  }

  void _stopPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── WebSocket ──
  //
  // 서버(`/api/notifications/ws`)는 알림 내용을 실어 보내지 않는다 — 새 알림이 생겼을 때
  // 빈 신호만 보낸다. 그래서 이 연결이 하는 일은 "폴백 폴링을 끄고, 신호가 올 때마다
  // refresh()를 부르는 것" 뿐이다. 신호 자체의 내용은 검사하지 않는다.

  void _connectWebSocket() {
    if (_stopped || _wsChannel != null) return;
    final Uri uri;
    try {
      uri = _buildWsUri();
    } catch (e) {
      // apiBaseUrl이 http(s)가 아닌 값으로 잘못 설정된 극단적인 경우 — 폴백 폴링만으로
      // 계속 동작하게 두고 재연결은 시도하지 않는다(어차피 URI가 안 바뀐다).
      debugPrint('[NotificationService] WS URI 구성 실패, 폴링만 사용: $e');
      return;
    }
    try {
      final channel = WebSocketChannel.connect(uri);
      _wsChannel = channel;
      _wsSubscription = channel.stream.listen(
        (_) {
          // 페이로드는 항상 빈 신호다 — 내용을 보지 않고 곧바로 다시 읽는다.
          _poll();
        },
        onDone: _onWsDisconnected,
        onError: (Object _) => _onWsDisconnected(),
        cancelOnError: true,
      );
      // web_socket_channel의 connect()는 즉시 예외를 던지지 않고 스트림에서 실패를
      // 알린다(웹 플랫폼 특성) — 그래서 "연결 시도 시작"과 "연결 성공"을 구분하지 않고
      // onDone/onError가 오기 전까지는 연결된 것으로 간주한다. 실패하면 아래 리스너가
      // 즉시 _onWsDisconnected를 부른다.
      _onWsConnected();
    } catch (e) {
      debugPrint('[NotificationService] WS 연결 실패, 폴링으로 계속: $e');
      _wsChannel = null;
      _scheduleWsReconnect();
    }
  }

  /// `AppConstants.apiBaseUrl`(예: `http://127.0.0.1:8000/api`)을 WS 엔드포인트로 바꾼다.
  /// http→ws, https→wss. 테스트유저 헤더(`X-Test-User-Id`)는 브라우저 WebSocket 핸드셰이크에
  /// 실어 보낼 수 없으므로 쿼리 파라미터로 대신 전달한다(서버 `notifications.py::notifications_ws`
  /// 와 같은 규약).
  Uri _buildWsUri() {
    final base = Uri.parse(AppConstants.apiBaseUrl);
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
    final testUserId = ApiService.testUserId;
    return base.replace(
      scheme: wsScheme,
      path: '${base.path}/notifications/ws',
      queryParameters: testUserId != null ? {'test_user_id': testUserId} : const {},
    );
  }

  void _onWsConnected() {
    _stopPollTimer(); // 깨움 신호가 그 역할을 대신한다.
  }

  void _onWsDisconnected() {
    _closeWebSocket();
    if (_stopped) return;
    _startPollTimer(); // 실시간 경로가 끊겼으니 폴백을 켠다.
    _scheduleWsReconnect();
  }

  void _closeWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
  }

  void _scheduleWsReconnect() {
    if (_stopped || _wsReconnectTimer != null) return;
    _wsReconnectTimer = Timer(
      const Duration(seconds: AppConstants.notificationWsReconnectDelaySeconds),
      () {
        _wsReconnectTimer = null;
        _connectWebSocket();
      },
    );
  }

  /// 개발/QA용 테스트유저 전환 시. 알림은 사용자별로 완전히 갈리므로 이전 사용자의
  /// 상태를 그대로 두면 (a) 남의 배지 숫자가 남고 (b) 미읽음 수가 튀면서 배너가
  /// 엉뚱하게 뜬다. 상태를 지우고 곧바로 다시 읽는다.
  ///
  /// WS 연결도 다시 맺는다 — 연결은 쿼리 파라미터로 특정 사용자에 묶여 있어서(`_buildWsUri`),
  /// 전환 후에도 이전 사용자 이름으로 붙어 있으면 새 사용자의 신호를 받지 못한다.
  ///
  /// 기준선은 `null`이 아니라 **빈 집합**으로 세운다. 앱 최초 시작(콜드 스타트,
  /// [start])은 기준선을 `null`로 둬서 첫 폴링이 "관측만 하고 배너는 안 띄우게" 한다
  /// (30분 묵은 알림이 튀어나오지 않게). 하지만 테스트유저 전환은 **다른 사람으로
  /// 로그인하는 것과 같다** — 전환 직후 그 사용자에게 이미 와 있는 미읽음은 이번
  /// 세션에서는 처음 보는 것이므로, 콜드 스타트와 달리 배너로 띄워야 한다. 빈 집합을
  /// 기준선으로 주면 다음 폴링에서 현재 미읽음 전부가 "새로 나타난 id"로 판정된다.
  void resetForUserSwitch() {
    _items = const [];
    _unreadCount = 0;
    _lastObservedUnreadIds = <String>{};
    _bannerEntry = null;
    _backlogUnreadCount = null; // 계정 전환은 재접속 요약 경로가 아니라 실시간 배너 경로를 탄다.
    notifyListeners();
    _closeWebSocket();
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    if (!_stopped) _connectWebSocket();
    _poll();
  }

  /// 배경 폴링 1회. **실패를 삼킨다** — 사용자가 시작하지 않은 동작의 실패를
  /// 다이얼로그/스낵바로 알리지 않는다(P12). 다음 주기에 다시 시도한다.
  Future<void> _poll() async {
    try {
      await refresh();
    } catch (e) {
      // 화면에는 아무것도 띄우지 않는다. 직전에 성공한 목록/배지가 그대로 남는다.
      debugPrint('[NotificationService] 폴링 실패(무시하고 다음 주기 대기): $e');
    }
  }

  /// 서버에서 목록을 다시 읽어 상태를 갱신한다.
  ///
  /// 실패는 **그대로 던진다.** 조용히 처리할지 사용자에게 보여줄지는 호출부가 정한다:
  /// 배경 폴링([_poll])은 삼키고, 목록 화면의 새로고침은 에러 화면으로 보여준다.
  Future<void> refresh() {
    return _inFlight ??= _fetchAndApply().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetchAndApply() async {
    final result = await _api.fetchNotifications();
    _applyList(result);
  }

  void _applyList(NotificationList result) {
    _items = result.items;
    _unreadCount = result.unreadCount;

    final currentUnreadIds = result.items.where((e) => !e.isRead).map((e) => e.id).toSet();
    final previousIds = _lastObservedUnreadIds;
    _lastObservedUnreadIds = currentUnreadIds;

    // 첫 관측(previousIds == null) = 재접속. 밀린 미읽음이 있으면 요약 다이얼로그
    // 신호([_backlogUnreadCount])를 세운다 — 최대 노출 원칙(사용자 정책, 9절)이라
    // "안 본 사이 쌓인 것"도 배지로만 두지 않는다. 이후 관측부터는 **직전에 없던 id가
    // 새로 나타났을 때만** 실시간 배너를 띄운다 — 개수가 아니라 id 집합으로 비교하므로,
    // 같은 폴링 주기 안에서 한 건이 만료로 빠지고 한 건이 새로 와도 개수가 우연히
    // 같아지는 것과 무관하게 새 id를 놓치지 않는다.
    if (previousIds == null) {
      // items(currentUnreadIds)는 서버 limit(NOTIFICATION_LIST_LIMIT)까지만 온다 —
      // 진짜 전체 미읽음 수는 배지와 같은 result.unreadCount를 써야 한다. items 길이를
      // 쓰면 미읽음이 limit을 넘었을 때 요약 다이얼로그와 배지 숫자가 서로 달라진다.
      if (result.unreadCount > 0) _backlogUnreadCount = result.unreadCount;
    } else {
      final newIds = currentUnreadIds.difference(previousIds);
      if (newIds.isNotEmpty) {
        final fresh = _newestAmong(result.items, newIds);
        if (fresh != null) _bannerEntry = fresh;
      }
    }

    // 배너로 띄워둔 알림이 이미 읽혔거나 만료돼 목록에서 사라졌으면 배너도 걷는다.
    final banner = _bannerEntry;
    if (banner != null) {
      final stillPending = result.items.any((e) => e.id == banner.id && !e.isRead);
      if (!stillPending) _bannerEntry = null;
    }

    notifyListeners();
  }

  /// 서버가 최신순으로 정렬해 주므로 [ids] 중 먼저 나오는 항목이 가장 최근 것이다.
  /// 여러 건이 한꺼번에 새로 나타나도 배너는 가장 최근 1건만 띄운다 —
  /// 나머지는 배지 숫자와 목록 화면에서 확인한다.
  NotificationEntry? _newestAmong(List<NotificationEntry> items, Set<String> ids) {
    for (final e in items) {
      if (ids.contains(e.id)) return e;
    }
    return null;
  }

  /// 사용자가 배너(다이얼로그)를 닫았을 때. 서버 상태는 건드리지 않는다
  /// (읽음이 아니라 "이 다이얼로그를 그만 그린다"일 뿐이라, 알림은 목록에 미읽음으로 남는다).
  void dismissBanner() {
    if (_bannerEntry == null) return;
    _bannerEntry = null;
    notifyListeners();
  }

  /// 재접속 요약 다이얼로그를 닫았을 때. [dismissBanner]와 같은 이유로 서버 상태는
  /// 건드리지 않는다 — 요약을 봤다는 것과 안의 알림들을 읽었다는 것은 다르다.
  void dismissBacklogSummary() {
    if (_backlogUnreadCount == null) return;
    _backlogUnreadCount = null;
    notifyListeners();
  }

  /// 알림 1건 읽음 처리. 사용자가 배너나 목록 항목을 직접 탭했을 때만 부른다.
  /// 실패는 그대로 던진다 — 사용자가 시작한 동작이므로 호출부가 메시지를 보여준다.
  Future<void> markRead(String notificationId) async {
    final result = await _api.markNotificationRead(notificationId);
    _applyReadResult(result, readIds: {notificationId});
  }

  /// 미읽음 전체 읽음 처리("모두 읽음" 버튼).
  Future<void> markAllRead() async {
    final result = await _api.markAllNotificationsRead();
    _applyReadResult(result, readIds: _items.map((e) => e.id).toSet());
  }

  /// 서버가 돌려준 미읽음 수를 곧바로 반영한다 — 목록을 한 번 더 읽지 않는다.
  /// 로컬 [items]의 is_read도 함께 맞춰야 배지와 목록이 어긋나지 않는다.
  void _applyReadResult(NotificationReadResult result, {required Set<String> readIds}) {
    _unreadCount = result.unreadCount;
    // 읽은 id는 기준선에서도 지운다 — 그래야 다음 폴링에서 그 id가 우연히 다시 미읽음으로
    // 보여도(서버 경합 등) "새로 나타난 것"으로 옳게 판정된다.
    _lastObservedUnreadIds = _lastObservedUnreadIds?.difference(readIds);
    _items = _items.map((e) => readIds.contains(e.id) ? _markedRead(e) : e).toList();

    final banner = _bannerEntry;
    if (banner != null && readIds.contains(banner.id)) _bannerEntry = null;

    notifyListeners();
  }

  /// 읽음 처리된 사본. `read_at`의 정확한 값은 서버만 알지만(응답에 없다) 화면이
  /// 쓰는 것은 [NotificationEntry.isRead]뿐이라, 다음 폴링에서 서버 값으로 덮인다.
  NotificationEntry _markedRead(NotificationEntry e) {
    if (e.isRead) return e;
    return NotificationEntry(
      id: e.id,
      type: e.type,
      spotContentId: e.spotContentId,
      spotName: e.spotName,
      questionId: e.questionId,
      body: e.body,
      createdAt: e.createdAt,
      expiresAt: e.expiresAt,
      readAt: DateTime.now().toUtc(),
      isRead: true,
    );
  }

  /// 싱글턴이라 실제로 버려지지 않는다. 실수로 dispose가 불려도 타이머는 정리한다.
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
