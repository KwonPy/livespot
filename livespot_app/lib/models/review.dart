class Review {
  final String id;
  final String userId;
  final String userName;
  final String spotId;
  final String spotName;
  final String content;
  final List<String> imageUrls;
  final bool isGpsVerified;
  final DateTime createdAt;
  final int likes;
  final int comments;

  Review({
    required this.id,
    required this.userId,
    required this.userName,
    required this.spotId,
    required this.spotName,
    required this.content,
    this.imageUrls = const [],
    this.isGpsVerified = false,
    required this.createdAt,
    this.likes = 0,
    this.comments = 0,
  });
}
