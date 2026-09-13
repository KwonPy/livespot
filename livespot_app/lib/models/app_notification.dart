// 기능 8(질문/답변 알림)의 응답 모델들.
//
// 서버는 전부 snake_case로 응답하고 시각은 타임존 접미사가 없는 naive UTC다
// (02_backend_contract.md 머리말). 'Z'를 붙이지 않고 파싱하면 로컬 시각으로 오인해
// 9시간 어긋난다 — HotspotEntry._parseUtc와 같은 패턴을 쓴다.
DateTime _parseUtc(String value) {
  final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  return DateTime.parse(hasTz ? value : '${value}Z');
}

/// 알림 1건. `type`은 **`NEW_QUESTION`(현장에 새 질문이 올라옴) / `NEW_ANSWER`(내 질문에
/// 답변이 달림) 2종**이다. 015가 잠시 `NEW_ANSWER` 1종으로 좁혔다가 같은 날 사용자 정정으로
/// 원복됐다(`01_spec.md` 2-2절) — 없앤 것은 알림 **목록 페이지**이지 알림 종류가 아니다.
/// 화면은 [isNewAnswer]로 둘을 구분한다(모달 문구·아이콘, 질문 카드 강조 대상 판정).
///
/// [body]는 **서버가 조립한 문구**다. 앱은 그대로 그린다 — 종류별 문구를 앱에서
/// 다시 조립하면 서버가 문구를 바꿨을 때 두 곳이 갈라진다(설계 원칙 1).
class NotificationEntry {
  final String id;
  final String type; // NEW_QUESTION / NEW_ANSWER
  final String spotContentId;
  final String? spotName; // TourAPI 조회 실패·삭제 시 null → 화면이 폴백 문구를 그린다
  final String? questionId; // 탭 시 이동할 질문. 스키마상 Optional
  final String body;
  final DateTime createdAt;

  /// **연결된 질문이 만료되는 시각**(질문 등록 후 2시간, P22·P24).
  /// 이전 구현의 "알림 자체가 생성 후 30분 뒤 만료"가 아니다 — 알림마다 값이 다르므로
  /// 남은 시간을 전역 상수로 계산하면 안 되고, 이 필드를 항목별로 써야 한다.
  final DateTime expiresAt;
  final DateTime? readAt; // 미읽음이면 null
  final bool isRead; // readAt != null과 동치. 서버가 함께 내려준다

  NotificationEntry({
    required this.id,
    required this.type,
    required this.spotContentId,
    this.spotName,
    this.questionId,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    this.readAt,
    required this.isRead,
  });

  bool get isNewAnswer => type == 'NEW_ANSWER';

  /// 관광지 이름 폴백. 기존 MyPage 목록들(bookmarks_screen:52, my_reports_screen:83,
  /// my_qna_screen:119)과 **같은 문구**를 쓴다 — 화면마다 다른 문구를 쓰면 같은 원인의
  /// 증상이 서로 다른 문제처럼 보인다.
  String get displaySpotName => spotName ?? '관광지 정보 없음 (ID $spotContentId)';

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    return NotificationEntry(
      id: json['id'] as String,
      type: json['type'] as String,
      spotContentId: json['spot_content_id'] as String,
      spotName: json['spot_name'] as String?,
      questionId: json['question_id'] as String?,
      body: json['body'] as String,
      createdAt: _parseUtc(json['created_at'] as String),
      expiresAt: _parseUtc(json['expires_at'] as String),
      readAt: json['read_at'] == null ? null : _parseUtc(json['read_at'] as String),
      isRead: json['is_read'] as bool,
    );
  }
}

/// `GET /api/notifications` 응답 전체.
///
/// [unreadCount]는 만료 제외 기준이라 [items] 안의 미읽음 개수와 어긋나지 않는다.
///
/// 2026-09-10 방향 수정(P24)으로 `ttl_minutes`가 응답에서 사라졌다. 알림의 표시 기준이
/// "알림 자체의 수명 30분"에서 "연결된 질문이 아직 2시간 유효한가"로 바뀌어, 전역 수명
/// 값이라는 개념 자체가 없어졌기 때문이다. 남은 시간은 항목별
/// [NotificationEntry.expiresAt]으로 계산한다.
class NotificationList {
  final List<NotificationEntry> items;
  final int unreadCount;

  NotificationList({
    required this.items,
    required this.unreadCount,
  });

  factory NotificationList.fromJson(Map<String, dynamic> json) {
    return NotificationList(
      items: (json['items'] as List<dynamic>)
          .map((e) => NotificationEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      unreadCount: json['unread_count'] as int,
    );
  }
}

/// 읽음 처리(`/read`, `/read-all`) 응답. 둘 다 멱등이라 이미 읽은 것을 다시 눌러도
/// 200 + [updatedCount] 0이 온다. [unreadCount]는 처리 후 남은 미읽음 수라
/// 앱이 배지를 곧바로 갱신할 수 있다.
class NotificationReadResult {
  final int updatedCount;
  final int unreadCount;

  NotificationReadResult({required this.updatedCount, required this.unreadCount});

  factory NotificationReadResult.fromJson(Map<String, dynamic> json) {
    return NotificationReadResult(
      updatedCount: json['updated_count'] as int,
      unreadCount: json['unread_count'] as int,
    );
  }
}

// 2026-09-13(015): 전역 알림 스위치 모델 `PushSettings`(`/notifications/push-settings`)를
// 제거했다. 사용자 정책으로 알림 ON/OFF 토글 자체가 사라져 앱에 켜짐/꺼짐이라는 상태가
// 없다 — 알림은 항상 켜져 있다.
//
// ⚠️ 기능 3의 관광지별 설정(`/notifications/settings`, `NotificationSetting`, 기본 꺼짐)은
// 이름만 비슷한 **다른 API**이고 그대로 살아 있다.
