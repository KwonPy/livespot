import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../models/spot.dart';
import '../../models/hotspot_entry.dart';
import '../../models/question.dart';
import '../../utils/formatters.dart';
import '../../utils/image_url.dart';
import '../../widgets/quick_report_modal.dart';
import '../../widgets/qa_section.dart';
import '../../widgets/global_qa_list.dart';
import '../../widgets/gps_verified_badge.dart';
import '../../widgets/pending_questions_banner.dart';
import '../detail/spot_detail_screen.dart';

enum _GpsMatchStatus { idle, loading, matched, none, error }

/// Live 페이지. 구조는 정책에 따라 고정된다.
///   GPS OFF                 : HOT SPOTS → 전체 LIVE Q&A
///   GPS ON + 현장 인증 성공  : 내 현장 Q&A → HOT SPOTS → 전체 LIVE Q&A
/// 개별 현장 제보 목록(코멘트 스트림)은 Live 메인에서 노출하지 않는다 — 제보 원문은
/// 관광지 상세페이지에서 계속 확인할 수 있다(데이터는 DB에 그대로 저장됨).
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  // GPS 연동 토글을 껐다 켜기 전까지는 위치 확인을 하지 않는다 — 탭을 열자마자
  // 위치 권한 팝업이 뜨는 걸 피하기 위해 기본값은 꺼짐.
  bool _isGpsVerified = false;
  _GpsMatchStatus _gpsMatchStatus = _GpsMatchStatus.idle;
  Spot? _gpsMatchedSpot;
  String? _gpsMatchError;

  // ── 기능 6(현장 사용자 수 집계) ──
  // 아래 3분 타이머의 verify-location 호출이 곧 위치 신호다(Q1-C). 신규 API도 신규
  // 타이머도 없다 — 여기서 하는 일은 "이미 보내고 있던 신호"의 응답을 화면에 쓰는 것뿐.
  //
  // null = 아직 못 읽었거나 조회에 실패함 → 표기를 아예 숨긴다.
  // 0    = 서버가 "최근 30분 안에 아무도 없었다"고 답한 값 → "0명"으로 그린다.
  // 이 둘을 뭉개면 조회 실패가 "0명"으로 보인다.
  int? _onsiteUserCount;
  // 위치 신호 응답에 실려 온 답변 대기 질문(Q6-A). presence_registered == true일 때만 채운다.
  List<Question> _pendingQuestions = [];

  // 현장 인증 상태는 영구적이지 않고 일정 시간 동안만 유효하다(정책) — GPS 연동이
  // 켜져 있는 동안 주기적으로 인증을 다시 확인해, 사용자가 자리를 뜨면 "내 현장 Q&A"가
  // 자동으로 사라지게 한다. 실제 쓰기(제보/답변)는 이 캐시된 상태를 믿지 않고 매번
  // 서버가 좌표를 다시 검증한다(기존 구현) — 이 타이머는 어디까지나 화면 표시용이다.
  Timer? _gpsRecheckTimer;
  static const _gpsRecheckInterval = Duration(minutes: 3);

  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  late Future<List<HotspotEntry>> _hotspotsFuture;

  @override
  void initState() {
    super.initState();
    _hotspotsFuture = _apiService.fetchHotspots();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(_animationController);
  }

  @override
  void dispose() {
    _gpsRecheckTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _onToggleGps(bool value) async {
    setState(() => _isGpsVerified = value);
    _gpsRecheckTimer?.cancel();
    if (value) {
      await _refreshGpsMatch();
      // 조용히 재확인 — 사용자가 질문 상세를 보고 있는 동안 매번 로딩 스피너로
      // 화면이 깜빡이지 않도록, 주기 재확인은 상태가 실제로 바뀔 때만 갱신한다.
      _gpsRecheckTimer = Timer.periodic(_gpsRecheckInterval, (_) => _refreshGpsMatch(silent: true));
    } else {
      setState(() {
        _gpsMatchStatus = _GpsMatchStatus.idle;
        _gpsMatchedSpot = null;
        _gpsMatchError = null;
        _onsiteUserCount = null;
        _pendingQuestions = [];
      });
    }
  }

  // GPS 연동: 현재 위치에서 실제로 100m+오차(150m) 이내로 인증되는 관광지가 있을 때만
  // "내 현장 Q&A"를 노출한다. 여러 관광지가 주변에 있어도 임의로 아무거나 고르지 않고,
  // 가장 가까운 후보를 서버 인증(verify-location)으로 재확인한다.
  Future<void> _refreshGpsMatch({bool silent = false}) async {
    if (!silent && mounted) setState(() => _gpsMatchStatus = _GpsMatchStatus.loading);
    try {
      final position = await _locationService.getCurrentPosition();
      final nearby = await _apiService.fetchNearbySpots(position.latitude, position.longitude, radius: 500);
      if (nearby.isEmpty) {
        if (mounted) {
          setState(() {
            _gpsMatchStatus = _GpsMatchStatus.none;
            _onsiteUserCount = null;
            _pendingQuestions = [];
          });
        }
        return;
      }
      final candidate = nearby.first;
      // 이 호출이 곧 위치 신호다 — 서버가 반경 판정을 통과시키면 presence를 갱신하고
      // 답변 대기 질문을 함께 실어 보낸다(기능 6, Q1-C).
      final verify = await _apiService.verifyLocation(candidate.contentId, position.latitude, position.longitude);
      if (!mounted) return;
      if (verify.verified) {
        setState(() {
          _gpsMatchStatus = _GpsMatchStatus.matched;
          _gpsMatchedSpot = candidate;
          // presence가 실제로 등록된 경우에만 대기 질문을 담는다. 인증되지 않은
          // 사용자에게 답변 버튼이 보이는 경로를 데이터 단계에서 없앤다.
          _pendingQuestions = verify.presenceRegistered ? verify.pendingQuestions : [];
        });
        await _fetchOnsiteCount(candidate.contentId);
      } else {
        setState(() {
          _gpsMatchStatus = _GpsMatchStatus.none;
          _gpsMatchedSpot = null;
          _onsiteUserCount = null;
          _pendingQuestions = [];
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsMatchStatus = _GpsMatchStatus.error;
        _gpsMatchedSpot = null;
        _onsiteUserCount = null;
        _pendingQuestions = [];
        _gpsMatchError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // 현장 인원은 상세페이지와 **같은** LiveStatusResponse에서 꺼낸다 — 인원 전용
  // 엔드포인트를 만들지 않는다(P13). 인증 성공 직후에 부르므로 방금 보낸 내 신호도
  // 이미 반영돼 있다.
  //
  // 실패해도 GPS 인증 자체는 성공한 상태라 "내 현장 Q&A"를 지우지 않는다. 인원 표기만
  // 사라진다(null) — 실패를 "0명"으로 적으면 없는 사실을 주장하는 셈이 된다.
  Future<void> _fetchOnsiteCount(String contentId) async {
    try {
      final status = await _apiService.fetchLiveStatus(contentId);
      if (mounted) setState(() => _onsiteUserCount = status.onsiteUserCount);
    } catch (_) {
      if (mounted) setState(() => _onsiteUserCount = null);
    }
  }

  // 이 탭에서는 대상 관광지가 미리 정해져 있지 않으므로, 현재 위치에서 가장 가까운
  // 관광지를 찾아 그 관광지에 대한 제보 창을 연다.
  Future<void> _openReportModalForNearestSpot(BuildContext context) async {
    try {
      final position = await _locationService.getCurrentPosition();
      final nearby = await _apiService.fetchNearbySpots(position.latitude, position.longitude, radius: 1000);
      if (!context.mounted) return;
      if (nearby.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('반경 1km 안에 제보할 수 있는 관광지가 없어요')),
        );
        return;
      }
      final nearest = nearby.first;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => QuickReportModal(spotName: nearest.title, spotContentId: nearest.contentId),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('현재 위치를 확인할 수 없어요: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openReportModalForNearestSpot(context),
        backgroundColor: LiveSpotTheme.primaryColor,
        icon: const Icon(Icons.bolt, color: Colors.white),
        label: const Text('실시간 제보하기', style: TextStyle(color: Colors.white, fontFamily: 'Pretendard', fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              if (_isGpsVerified) _buildMyOnsiteSection(),
              _buildHotspots(),
              const GlobalQaList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FadeTransition(
                opacity: _pulseAnimation,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF1744),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '라이브',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Pretendard',
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text('GPS 연동', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  Switch(
                    value: _isGpsVerified,
                    onChanged: (val) => _onToggleGps(val),
                    activeColor: LiveSpotTheme.primaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '실시간 현황',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }

  // ── 📍 내 현장 Q&A. GPS 연동이 켜져 있는 동안만 노출되는 슬롯 — 인증에 성공하면
  // 그 관광지의 Q&A(QaSection)를, 아직 확인 중이거나 인증된 곳이 없으면 그 상태를 보여준다.
  Widget _buildMyOnsiteSection() {
    switch (_gpsMatchStatus) {
      case _GpsMatchStatus.matched:
        final spot = _gpsMatchedSpot!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('📍 내 현장 · ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: LiveSpotTheme.primaryColor, fontFamily: 'Pretendard')),
                      Expanded(
                        child: Text(spot.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                      ),
                      const GpsVerifiedBadge(),
                    ],
                  ),
                  _buildOnsiteCountLine(),
                ],
              ),
            ),
            // Q6-A: 답변 대기 질문 배너. 위치 신호 응답에 실려 온 목록을 그대로 쓴다.
            PendingQuestionsBanner(
              questions: _pendingQuestions,
              spotName: spot.title,
              // 답변하면 신호를 다시 보내 대기 목록·인원을 서버 기준으로 갱신한다.
              onAnswered: () => _refreshGpsMatch(silent: true),
            ),
            QaSection(spotContentId: spot.contentId, spotName: spot.title, showAskButton: false, activeOnly: true),
          ],
        );
      case _GpsMatchStatus.loading:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('현재 위치 확인 중...', style: TextStyle(fontFamily: 'Pretendard')),
              ],
            ),
          ),
        );
      case _GpsMatchStatus.none:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              Icon(Icons.location_off, color: Colors.grey.shade400),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '인증된 관광지가 없어요.\n관광지 반경 150m 이내로 이동한 뒤 다시 시도해보세요.',
                  style: TextStyle(fontFamily: 'Pretendard', fontSize: 13),
                ),
              ),
            ],
          ),
        );
      case _GpsMatchStatus.error:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.shade100)),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade300),
              const SizedBox(width: 12),
              Expanded(
                child: Text('위치를 확인하지 못했어요: ${_gpsMatchError ?? ''}', style: const TextStyle(fontFamily: 'Pretendard', fontSize: 13)),
              ),
            ],
          ),
        );
      case _GpsMatchStatus.idle:
        return const SizedBox.shrink();
    }
  }

  // ── 기능 6: "지금 여기 N명" (Q5-B). 상세페이지 LIVE 상태창과 **같은** 서버 값
  // (LiveStatusResponse.onsite_user_count)을 쓴다 — 앱이 따로 세지 않는다.
  //
  // "지금 여기"는 답변을 부탁하는 맥락의 표현이고, 그 숫자의 실제 기준은 바로 옆에
  // 붙는 "최근 30분 기준"이다. 두 문구는 항상 붙어 다녀야 한다 — 기준을 떼면 "실시간
  // 접속자 수"라는, 우리가 알 수 없는 사실을 주장하게 된다(P6·P15).
  //
  // 조회하지 못했으면(null) 줄 자체를 감춘다. "0명"으로 적으면 실패가 사실로 둔갑한다.
  Widget _buildOnsiteCountLine() {
    final count = _onsiteUserCount;
    if (count == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.person_pin_circle_outlined, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            '지금 여기 $count명',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800], fontFamily: 'Pretendard'),
          ),
          const SizedBox(width: 6),
          Text(
            '· 최근 ${AppConstants.presenceWindowMinutes}분 기준',
            style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'Pretendard'),
          ),
        ],
      ),
    );
  }

  // ── 🔥 HOT SPOTS (TOP5). 1순위: 최근 실제 현장 제보, 2순위: 집중률 예측 — 서버가
  // 이미 이 우선순위로 정렬해 돌려준다(섞지 않고 소스별로 나열). ──
  Widget _buildHotspots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text('🔥 HOT SPOTS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
        ),
        FutureBuilder<List<HotspotEntry>>(
          future: _hotspotsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (snapshot.hasError) {
              // "활동 중인 관광지가 없어요"와 구분되게 보여준다 — 조회 자체가 실패한
              // 것과 정말 활동이 없는 것은 다른 상황이라 같은 문구로 뭉개면 원인을
              // 알 수 없게 된다.
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade300),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'HOT SPOTS를 불러오지 못했어요: ${snapshot.error.toString().replaceFirst('Exception: ', '')}',
                        style: const TextStyle(fontFamily: 'Pretendard', fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }
            final hotspots = snapshot.data ?? [];
            if (hotspots.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('지금 활동 중인 관광지가 없어요', style: TextStyle(color: Colors.grey, fontFamily: 'Pretendard'))),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: hotspots.length,
              itemBuilder: (context, index) {
                final spot = hotspots[index];
                final badgeColor = _levelColor(spot.displayLevel);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SpotDetailScreen(
                          // imageUrl을 빼먹으면 HOT SPOTS를 거쳐 들어간 상세페이지만
                          // 헤더 이미지가 없는 상태가 된다(다른 진입 경로와 달리).
                          spot: Spot(
                            contentId: spot.contentId,
                            title: spot.spotTitle,
                            address: spot.spotAddress,
                            imageUrl: spot.spotImageUrl,
                          ),
                        ),
                      ),
                    ),
                    leading: _hotspotLeading(spot, index + 1),
                    title: Text(spot.spotTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
                    subtitle: Text(_hotspotSubtitle(spot), style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Pretendard')),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                      child: Text(_levelLabel(spot), style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Color _levelColor(String level) => level == 'EASY' ? Colors.green : level == 'NORMAL' ? Colors.orange : Colors.red;

  // 제보 기반은 "여유/보통/혼잡", 집중률 기반은 "여유/보통/높음" — 문구만 봐도 어느 데이터
  // 출처인지 구분되게 한다(function.md 기능 9 원칙).
  /// HOT SPOTS 카드의 leading. 사진이 있으면 썸네일 + 좌하단 순위 배지,
  /// 없거나 로딩에 실패하면 기존 순위 CircleAvatar로 되돌아간다.
  /// 순위는 어느 경로로도 화면에서 사라지지 않는다 — 랭킹 목록에서 몇 등인지가
  /// 빠지면 목록의 의미 자체가 없어진다.
  Widget _hotspotLeading(HotspotEntry spot, int rank) {
    final rankAvatar = CircleAvatar(
      backgroundColor: LiveSpotTheme.primaryColor.withValues(alpha: 0.1),
      child: Text('$rank', style: const TextStyle(color: LiveSpotTheme.primaryColor, fontWeight: FontWeight.bold)),
    );

    // TourAPI CDN은 CORS 헤더를 안 보내므로 반드시 프록시를 거쳐야 웹에서 그려진다.
    final imageUrl = resolveImageUrl(spot.spotImageUrl);
    if (imageUrl == null) return rankAvatar;

    const double size = 44;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => rankAvatar,
            ),
          ),
          Positioned(
            left: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LiveSpotTheme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                '$rank',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Pretendard'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _levelLabel(HotspotEntry spot) {
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
      return '최근 현장 제보 ${Formatters.timeAgo(spot.lastReportAt!)}';
    }
    return '방문 집중도 예측 기반';
  }
}
