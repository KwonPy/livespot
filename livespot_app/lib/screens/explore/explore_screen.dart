import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../models/spot.dart';
import '../../models/hotspot_entry.dart';
import '../../utils/formatters.dart';
import '../detail/spot_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedCategoryIndex = 0;
  final ApiService _apiService = ApiService();
  late Future<List<Spot>> _spotsFuture;
  late Future<List<HotspotEntry>> _hotspotsFuture;

  final List<Map<String, dynamic>> _categories = [
    {'icon': Icons.landscape, 'label': '관광지', 'color': const Color(0xFF42A5F5)},
    {'icon': Icons.restaurant, 'label': '맛집', 'color': const Color(0xFFFF7043)},
    {'icon': Icons.museum, 'label': '문화시설', 'color': const Color(0xFF7E57C2)},
    {'icon': Icons.celebration, 'label': '축제', 'color': const Color(0xFFEC407A)},
    {'icon': Icons.sports_tennis, 'label': '레포츠', 'color': const Color(0xFF26A69A)},
    {'icon': Icons.hotel, 'label': '숙박', 'color': const Color(0xFF5C6BC0)},
    {'icon': Icons.shopping_bag, 'label': '쇼핑', 'color': const Color(0xFFFFA726)},
    {'icon': Icons.local_cafe, 'label': '카페', 'color': const Color(0xFF8D6E63)},
  ];

  @override
  void initState() {
    super.initState();
    _spotsFuture = _apiService.fetchSpots();
    _hotspotsFuture = _apiService.fetchHotspots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FutureBuilder<List<Spot>>(
          future: _spotsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('에러 발생: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('관광지 데이터가 없습니다.'));
            }

            final spots = snapshot.data!;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildSearchBar()),
                SliverToBoxAdapter(child: _buildCategoryGrid()),
                SliverToBoxAdapter(child: _buildTrendingSection(spots)),
                SliverToBoxAdapter(child: _buildAiRecommendSection(spots)),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('탐색', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey[400], size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(hintText: '여행지, 지역, 키워드로 검색', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14), border: InputBorder.none),
                  ),
                ),
                Icon(Icons.tune, color: Colors.grey[400], size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('카테고리', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategoryIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategoryIndex = index),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? (cat['color'] as Color).withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelected ? (cat['color'] as Color).withOpacity(0.4) : Colors.grey.withOpacity(0.1)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(cat['icon'] as IconData, color: cat['color'] as Color, size: 28),
                      const SizedBox(height: 6),
                      Text(cat['label'] as String, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? cat['color'] as Color : Colors.grey[600])),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingSection(List<Spot> spots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            const Text('🔥 인기 급상승', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () {}, child: Text('전체보기', style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
          ]),
        ),
        SizedBox(
          height: 190,
          child: FutureBuilder<List<HotspotEntry>>(
            future: _hotspotsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    '불러오지 못했어요: ${snapshot.error.toString().replaceFirst('Exception: ', '')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red[300], fontSize: 12),
                  ),
                );
              }
              final rankings = snapshot.data ?? [];
              if (rankings.isEmpty) {
                return Center(child: Text('지금 활동 중인 관광지가 없어요', style: TextStyle(color: Colors.grey[400])));
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: rankings.length,
                itemBuilder: (context, index) {
                  final r = rankings[index];
                  final spot = spots.where((s) => s.contentId == r.contentId).firstOrNull;
                  final crowdColor = r.displayLevel == 'EASY' ? Colors.green : r.displayLevel == 'NORMAL' ? Colors.orange : Colors.red;
                  return GestureDetector(
                    onTap: () {
                      if (spot != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)));
                      }
                    },
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 100,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [LiveSpotTheme.primaryColor.withOpacity(0.3), LiveSpotTheme.primaryColor.withOpacity(0.6)]),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: Stack(children: [
                              const Center(child: Icon(Icons.landscape, color: Colors.white54, size: 40)),
                              Positioned(top: 8, right: 8, child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: crowdColor.withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
                                child: Text(_hotspotLevelLabel(r), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              )),
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.spotTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(r.spotAddress ?? '위치 정보 없음', style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.edit_note, size: 12, color: Colors.grey[400]),
                                  const SizedBox(width: 2),
                                  Text(_hotspotSubtitle(r), style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAiRecommendSection(List<Spot> spots) {
    if (spots.isEmpty) return const SizedBox.shrink();
    
    final recommendations = [
      {'spot': spots.length > 5 ? spots[5] : spots[0], 'reason': '현재 한적하고 날씨 최적'},
      {'spot': spots.length > 2 ? spots[2] : spots[0], 'reason': '이번 주 맛집 축제 진행 중'},
      {'spot': spots.length > 4 ? spots[4] : spots[0], 'reason': '등반 최적 날씨, 주차 여유'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF7C4DFF)]), borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, color: Colors.white, size: 14), SizedBox(width: 4), Text('AI 추천', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))]),
            ),
            const SizedBox(width: 8),
            const Text('지금 방문하기 좋은 곳', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          ...recommendations.map((rec) {
            final spot = rec['spot'] as Spot;
            final reason = rec['reason'] as String;
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot))),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Row(children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(color: LiveSpotTheme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.place, color: LiveSpotTheme.primaryColor)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(spot.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(spot.address ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(4)),
                      child: Text('✨ $reason', style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32))),
                    ),
                  ])),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 제보 기반은 "여유/보통/혼잡", 집중률 기반은 "여유/보통/높음" — 문구만 봐도 어느 데이터
  // 출처인지 구분되게 한다(function.md 기능 9 원칙, live_screen.dart와 동일 로직).
  String _hotspotLevelLabel(HotspotEntry spot) {
    if (spot.isFromReport) {
      switch (spot.displayLevel) {
        case 'BUSY':
          return '혼잡';
        case 'NORMAL':
          return '보통';
        default:
          return '여유';
      }
    }
    switch (spot.displayLevel) {
      case 'BUSY':
        return '높음';
      case 'NORMAL':
        return '보통';
      default:
        return '여유';
    }
  }

  String _hotspotSubtitle(HotspotEntry spot) {
    if (spot.isFromReport && spot.lastReportAt != null) {
      return '${spot.reportCount}건 · ${Formatters.timeAgo(spot.lastReportAt!)}';
    }
    return '집중률 예측 기반';
  }
}
