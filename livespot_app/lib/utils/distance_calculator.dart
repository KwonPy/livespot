import 'dart:math';

class DistanceCalculator {
  static const double earthRadiusMeters = 6371000;

  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var dLat = _degreesToRadians(lat2 - lat1);
    var dLon = _degreesToRadians(lon2 - lon1);

    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
        
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static bool isWithinRadius(double lat1, double lon1, double lat2, double lon2, double radiusMeters) {
    return calculateDistance(lat1, lon1, lat2, lon2) <= radiusMeters;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}
