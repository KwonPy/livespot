import 'package:intl/intl.dart';

class Formatters {
  static String formatDate(DateTime date) {
    return DateFormat('yyyy.MM.dd').format(date);
  }

  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }
  
  static String formatDateTime(DateTime date) {
    return DateFormat('yyyy.MM.dd HH:mm').format(date);
  }

  static String timeAgo(DateTime date) {
    final diff = DateTime.now().toUtc().difference(date.toUtc());
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  static const Duration _kstOffset = Duration(hours: 9);
  static DateTime _toKst(DateTime date) => date.toUtc().add(_kstOffset);

  /// 현장 제보 이력 목록용 표기. 한국시간(KST) 달력일 기준으로 "오늘"이면 기존
  /// 분/시간 표기를 그대로 쓰고, 1~6일 전이면 "N일 전", 7일 이상이면 날짜(yyyy.MM.dd)로 표시한다.
  /// 백엔드의 "당일" 판정(기능 5, 현재 혼잡도/대기/주차)과 동일한 KST 자정 기준을 쓴다.
  static String reportRecency(DateTime date) {
    final nowKst = _toKst(DateTime.now());
    final dateKst = _toKst(date);
    final nowDay = DateTime(nowKst.year, nowKst.month, nowKst.day);
    final reportDay = DateTime(dateKst.year, dateKst.month, dateKst.day);
    final dayDiff = nowDay.difference(reportDay).inDays;

    if (dayDiff <= 0) return timeAgo(date);
    if (dayDiff < 7) return '$dayDiff일 전';
    return formatDate(dateKst);
  }
}
