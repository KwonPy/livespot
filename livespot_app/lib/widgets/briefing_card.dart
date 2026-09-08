import 'package:flutter/material.dart';
import '../models/spot.dart';
import '../models/live_status.dart';
import '../models/congestion_info.dart';
import '../models/weather.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../utils/image_url.dart';
import 'crowdedness_badge.dart';
import 'weather_badge.dart';
import 'live_badge.dart';
import '../screens/detail/spot_detail_screen.dart';

class BriefingCard extends StatefulWidget {
  final Spot spot;

  const BriefingCard({super.key, required this.spot});

  @override
  State<BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends State<BriefingCard> {
  late Future<LiveStatus> _liveStatusFuture;
  late Future<CongestionInfo> _congestionFuture;
  late Future<WeatherInfo> _weatherFuture;

  @override
  void initState() {
    super.initState();
    _liveStatusFuture = ApiService().fetchLiveStatus(widget.spot.contentId);
    _congestionFuture = ApiService().fetchCongestion(widget.spot.contentId);
    _weatherFuture = ApiService().fetchWeather(widget.spot.contentId);
  }

  @override
  void didUpdateWidget(covariant BriefingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spot.contentId != widget.spot.contentId) {
      _liveStatusFuture = ApiService().fetchLiveStatus(widget.spot.contentId);
      _congestionFuture = ApiService().fetchCongestion(widget.spot.contentId);
      _weatherFuture = ApiService().fetchWeather(widget.spot.contentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 상단: 이미지 + 정보
          Row(
            children: [
              // 대표 이미지
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // resolveImageUrl은 null·빈 문자열을 모두 null로 접어준다.
                child: resolveImageUrl(spot.imageUrl) != null
                    ? Image.network(
                        resolveImageUrl(spot.imageUrl)!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                      )
                    : _buildImagePlaceholder(),
              ),
              const SizedBox(width: 12),
              // 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (spot.address != null)
                      Text(
                        spot.address!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    // 배지들 — LIVE는 실제로 최근 2시간 안에 제보가 있을 때만 나타난다
                    // (평소엔 자리 자체가 생기지 않음).
                    Row(
                      children: [
                        // 실시간 날씨 — 하드코딩(28°/맑음)을 실제 API 결과로 교체했다.
                        FutureBuilder<WeatherInfo>(
                          future: _weatherFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              // 로딩 중: 자리를 잡아두지 않고 조용히 비운다(배지 폭이 문구마다 달라 흔들림 방지).
                              return const SizedBox.shrink();
                            }
                            if (snapshot.hasError) {
                              // 날씨는 이 카드의 부수 정보라 실패해도 에러 배너를 띄우지 않는다.
                              // 대신 배지 자체가 나타나지 않으므로 "정보 없음"(available:false)과 구분된다.
                              return const SizedBox.shrink();
                            }
                            final weather = snapshot.data;
                            if (weather == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: WeatherBadge(weather: weather),
                            );
                          },
                        ),
                        // 방문 집중률 예측(기능 9) — 지도 마커와 같은 소스의 값.
                        FutureBuilder<CongestionInfo>(
                          future: _congestionFuture,
                          builder: (context, snapshot) {
                            return CrowdednessBadge(level: snapshot.data?.level ?? 'unknown');
                          },
                        ),
                        FutureBuilder<LiveStatus>(
                          future: _liveStatusFuture,
                          builder: (context, snapshot) {
                            if (snapshot.data?.isLive != true) return const SizedBox.shrink();
                            return const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: LiveBadge(),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 요약 한 줄 — 바로 위 배지와 같은 값으로 조립한다.
          _buildSummaryLine(),
          // 자세히 보기 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SpotDetailScreen(spot: spot),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: LiveSpotTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '자세히 보기',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 요약 한 줄. **새 API 호출을 만들지 않고** 배지가 이미 쓰는 두 Future의 결과를
  /// 그대로 재사용한다.
  ///
  /// 예전에는 '☀️ 쾌적한 날씨, 여유로운 혼잡도 — 지금 방문 추천!'이 고정 문자열이었다.
  /// 배지는 실제 API로 교체됐는데 이 줄만 남아서, 배지가 '23° 구름 조금 / 높음'을
  /// 보여주는 동안 바로 아래에서 정반대를 말하는 모순이 생겼다.
  /// 값을 반영하지 못하는 상태(로딩·실패)에서는 절대 단정하지 않고 중립 문구로 두거나
  /// 줄 자체를 숨긴다 — 못 그리면 숨기는 쪽이 정직하다.
  Widget _buildSummaryLine() {
    return FutureBuilder<WeatherInfo>(
      future: _weatherFuture,
      builder: (context, weatherSnap) {
        return FutureBuilder<CongestionInfo>(
          future: _congestionFuture,
          builder: (context, congestionSnap) {
            final loading =
                weatherSnap.connectionState == ConnectionState.waiting ||
                    congestionSnap.connectionState == ConnectionState.waiting;
            if (loading) {
              // 도착 전에는 아무 판정도 하지 않는다. 자리를 유지해 문구 등장 시 레이아웃이 튀지 않게 한다.
              return _summaryContainer('현재 상황을 불러오는 중');
            }
            // 실패한 쪽은 문구에서 통째로 빠진다. 추측해서 채우지 않는다.
            // (날씨/집중률은 이 카드의 부수 정보라 에러 배너는 띄우지 않는다 — 배지와 같은 정책.)
            final weather = weatherSnap.hasError ? null : weatherSnap.data;
            final congestion = congestionSnap.hasError ? null : congestionSnap.data;

            final text = _summaryText(weather, congestion);
            if (text == null) return const SizedBox.shrink();
            return _summaryContainer(text);
          },
        );
      },
    );
  }

  /// 서버가 준 값만 이어 붙인다. 앱이 쾌적함·추천 여부를 판정하지 않는다.
  /// 양쪽 다 쓸 값이 없으면 null → 호출부가 줄을 통째로 숨긴다.
  static String? _summaryText(WeatherInfo? weather, CongestionInfo? congestion) {
    final parts = <String>[];

    // available:false면 서버가 temp를 null로 채워 보낸다. 그때는 날씨 조각을 넣지 않는다.
    if (weather != null && weather.available && weather.temp != null) {
      parts.add('${weather.temp!.round()}° ${weather.description}');
    }

    // 집중률은 "예측" 어휘(여유/보통/높음)를 배지와 공유한다 — 실측 제보 어휘와 섞지 않는다.
    if (congestion != null) {
      final label = CrowdednessBadge.labelFor(congestion.level);
      if (label != null) {
        final rate = congestion.congestionRate;
        parts.add(rate == null
            ? '방문 집중률 $label'
            : '방문 집중률 $label(${rate.round()}%)');
      }
    }

    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  Widget _summaryContainer(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E88E5).withOpacity(0.05),
              const Color(0xFF7C4DFF).withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF7C4DFF).withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 16,
              color: Color(0xFF7C4DFF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: LiveSpotTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.landscape, color: LiveSpotTheme.primaryColor, size: 32),
    );
  }
}
