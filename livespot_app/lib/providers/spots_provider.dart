import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/spot.dart';
import '../services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final spotsProvider = FutureProvider<List<Spot>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.fetchSpots();
});
