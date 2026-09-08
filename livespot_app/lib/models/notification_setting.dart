class NotificationSetting {
  final String contentId;
  final bool pushEnabled;

  NotificationSetting({required this.contentId, required this.pushEnabled});

  factory NotificationSetting.fromJson(Map<String, dynamic> json) {
    return NotificationSetting(
      contentId: json['content_id'] as String,
      pushEnabled: json['push_enabled'] as bool,
    );
  }
}
