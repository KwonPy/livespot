class Spot {
  final String contentId;
  final String title;
  final String? address;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String? category;
  final String? overview;
  final String? tel;
  final double? dist; // 거리 (미터), nearby 검색 시에만 포함

  Spot({
    required this.contentId,
    required this.title,
    this.address,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.category,
    this.overview,
    this.tel,
    this.dist,
  });

  factory Spot.fromJson(Map<String, dynamic> json) {
    return Spot(
      contentId: json['content_id'] ?? '',
      title: json['title'] ?? '',
      address: json['address'],
      imageUrl: json['image_url'],
      latitude: json['mapy']?.toDouble(),
      longitude: json['mapx']?.toDouble(),
      category: json['content_type_id'],
      overview: json['overview'],
      tel: json['tel'],
      dist: json['dist']?.toDouble(),
    );
  }
}
