import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/gps_verified_badge.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 데모 피드 데이터
  final List<Map<String, dynamic>> _feedItems = [
    {
      'userName': '여행자김',
      'userInitial': '김',
      'spotName': '경복궁',
      'location': '서울 종로구',
      'content': '오후 3시 기준 경복궁 관람 쾌적합니다! 외국인 관광객이 좀 있지만 여유롭게 관람 가능해요. 한복 대여점도 웨이팅 없이 바로 이용 가능합니다 👍',
      'rating': 5,
      'gpsVerified': true,
      'timeAgo': '5분 전',
      'likes': 23,
      'comments': 4,
      'crowdedness': 'green',
      'hasImage': true,
    },
    {
      'userName': '부산사람',
      'userInitial': '부',
      'spotName': '해운대해수욕장',
      'location': '부산 해운대구',
      'content': '지금 해운대 완전 사람 많아요! 파라솔 자리 없으니 일찍 오세요. 물은 깨끗하고 파도 적당합니다 🌊',
      'rating': 4,
      'gpsVerified': true,
      'timeAgo': '15분 전',
      'likes': 45,
      'comments': 12,
      'crowdedness': 'red',
      'hasImage': true,
    },
    {
      'userName': '제주도민',
      'userInitial': '제',
      'spotName': '성산일출봉',
      'location': '제주 서귀포시',
      'content': '오늘 날씨 최고! 정상까지 등반 약 30분 소요. 바람이 좀 불지만 경치가 끝내줍니다. 주차장은 70% 정도 차있어요.',
      'rating': 5,
      'gpsVerified': true,
      'timeAgo': '32분 전',
      'likes': 67,
      'comments': 8,
      'crowdedness': 'yellow',
      'hasImage': false,
    },
    {
      'userName': '맛집헌터',
      'userInitial': '맛',
      'spotName': '전주 한옥마을',
      'location': '전북 전주시',
      'content': '한옥마을 맛집 탐방 중! 비빔밥 골목은 웨이팅 20분 정도. 카페거리는 여유롭습니다 ☕',
      'rating': 4,
      'gpsVerified': false,
      'timeAgo': '1시간 전',
      'likes': 31,
      'comments': 6,
      'crowdedness': 'yellow',
      'hasImage': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Text(
                    '실시간 피드',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.notifications_none, color: Colors.grey),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            // 탭 바
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: '🕐 최신순'),
                  Tab(text: '🔥 인기순'),
                ],
              ),
            ),
            // 피드 리스트
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFeedList(_feedItems),
                  _buildFeedList([..._feedItems]..sort(
                      (a, b) => (b['likes'] as int).compareTo(a['likes'] as int),
                    )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedList(List<Map<String, dynamic>> items) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(seconds: 1));
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildFeedCard(items[index]),
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> item) {
    final crowdColor = item['crowdedness'] == 'green'
        ? LiveSpotTheme.successColor
        : item['crowdedness'] == 'yellow'
            ? LiveSpotTheme.warningColor
            : LiveSpotTheme.dangerColor;
    final crowdText = item['crowdedness'] == 'green'
        ? '여유'
        : item['crowdedness'] == 'yellow'
            ? '보통'
            : '혼잡';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 유저 정보 & 시간
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: LiveSpotTheme.primaryColor.withOpacity(0.15),
                child: Text(
                  item['userInitial'],
                  style: const TextStyle(
                    color: LiveSpotTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item['userName'],
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        if (item['gpsVerified'] == true) const GpsVerifiedBadge(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 2),
                        Text(
                          '${item['spotName']} · ${item['location']}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                item['timeAgo'],
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 혼잡도 배지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: crowdColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, size: 14, color: crowdColor),
                const SizedBox(width: 4),
                Text(
                  '현재 $crowdText',
                  style: TextStyle(fontSize: 11, color: crowdColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 리뷰 내용
          Text(
            item['content'],
            style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey[800]),
          ),
          // 이미지 플레이스홀더
          if (item['hasImage'] == true)
            Container(
              margin: const EdgeInsets.only(top: 10),
              height: 160,
              decoration: BoxDecoration(
                color: LiveSpotTheme.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.image, color: LiveSpotTheme.primaryColor, size: 40),
              ),
            ),
          const SizedBox(height: 10),
          // 별점 + 액션 버튼
          Row(
            children: [
              // 별점
              ...List.generate(
                5,
                (i) => Icon(
                  i < item['rating'] ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 16,
                  color: const Color(0xFFFFB74D),
                ),
              ),
              const Spacer(),
              // 좋아요
              _buildActionButton(Icons.favorite_border, '${item['likes']}'),
              const SizedBox(width: 14),
              // 댓글
              _buildActionButton(Icons.chat_bubble_outline, '${item['comments']}'),
              const SizedBox(width: 14),
              // 공유
              Icon(Icons.share_outlined, size: 18, color: Colors.grey[400]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(count, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }
}
