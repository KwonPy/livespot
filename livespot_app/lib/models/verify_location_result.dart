class VerifyLocationResult {
  final bool verified;
  final double distanceM;
  final int thresholdM;
  final String message;

  VerifyLocationResult({
    required this.verified,
    required this.distanceM,
    required this.thresholdM,
    required this.message,
  });

  factory VerifyLocationResult.fromJson(Map<String, dynamic> json) {
    return VerifyLocationResult(
      verified: json['verified'] as bool,
      distanceM: (json['distance_m'] as num).toDouble(),
      thresholdM: json['threshold_m'] as int,
      message: json['message'] as String,
    );
  }
}
