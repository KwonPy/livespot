import '../models/spot.dart';

/// 앱 전체에서 사용하는 중앙 집중식 Mock 데이터 서비스
/// 추후 실제 API(TourAPI, Firebase 등) 연동 시 이 클래스만 교체하면 됩니다.
class MockDataService {
  // ──────────────────── 싱글톤 ────────────────────
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal();

  // ──────────────────── 참여 유도 문구 (Motivation Texts) ────────────────────
  List<String> getMotivationTexts() {
    return [
      '다음 여행자를 도와주세요. 🤝',
      '현재 현장에 있는 당신만 답할 수 있습니다. 📍',
      '여행자가 당신의 도움을 기다리고 있습니다. 💡',
      '당신의 한마디가 누군가의 여행을 바꿀 수 있어요. ✨',
      '30초만 투자해서 다음 여행자를 도와주세요! 🎯',
    ];
  }

  // ──────────────────── 혼잡도 라벨 헬퍼 ────────────────────
  static String crowdednessLabel(String code) {
    switch (code) {
      case 'EASY': return '여유';
      case 'NORMAL': return '보통';
      case 'BUSY': return '혼잡';
      default: return '정보없음';
    }
  }

  static String waitingTimeLabel(String code) {
    switch (code) {
      case 'NONE': return '없음';
      case 'UNDER_10': return '10분 이하';
      case '10_TO_30': return '10~30분';
      case 'OVER_30': return '30분 이상';
      default: return '정보없음';
    }
  }

  static String parkingLabel(String code) {
    switch (code) {
      case 'EASY': return '여유';
      case 'NORMAL': return '보통';
      case 'FULL': return '만차';
      default: return '정보없음';
    }
  }
}
