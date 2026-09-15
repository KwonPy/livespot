import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/spot.dart';
import '../../models/report.dart';
import '../../models/live_status.dart';
import '../../models/congestion_info.dart';
import '../../models/weather.dart';
import '../../models/briefing.dart';
import '../../models/question.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../utils/image_url.dart';
import '../../services/mock_data_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/gps_verified_badge.dart';
import '../../widgets/login_required_sheet.dart';
import '../../widgets/quick_report_modal.dart';
import '../../widgets/crowdedness_badge.dart';
import '../../widgets/weather_badge.dart';
import '../../widgets/qa_section.dart';
import '../../widgets/pending_questions_banner.dart';

class SpotDetailScreen extends ConsumerStatefulWidget {
  final Spot spot;

  const SpotDetailScreen({super.key, required this.spot});

  @override
  ConsumerState<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends ConsumerState<SpotDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _typingController;
  // AI 브리핑(기능 10). _briefing이 채워진 뒤에야 타이핑이 시작된다 — 표시할 문장을
  // 서버에서 받기 전에는 애니메이션을 돌릴 대상 자체가 없다.
  Briefing? _briefing;
  bool _briefingLoading = true;
  String _briefingFullText = ''; // 타이핑 대상 원문
  String _displayedBriefing = ''; // 지금까지 찍힌 부분
  int _charIndex = 0;
  LiveStatus? _liveStatus;
  bool _liveStatusLoading = true;
  // 조회 실패와 "0건 / 0명"을 화면에서 구분하기 위한 플래그. 자세한 이유는 _fetchLiveStatus 주석.
  bool _liveStatusError = false;
  CongestionInfo? _congestionInfo; // 방문 집중률 "예측" (기능 9)
  bool _congestionLoading = true;
  WeatherInfo? _weather; // 실시간 날씨. null = 로딩 중이거나 조회 자체가 실패한 상태

  Map<String, dynamic>? _spotDetail;
  Map<String, dynamic>? _spotIntro;
  bool _overviewExpanded = false; // "관광지 소개" 5줄 초과 시 더보기/접기 토글

  List<Report> _reports = [];
  bool _reportsLoading = true;

  final LocationService _locationService = LocationService();
  bool? _pushEnabled; // null = 로딩 전
  bool? _bookmarked; // null = 로딩 전 → 버튼 비활성
  bool _verifyingOnsite = false;

  // 기능 6(현장 사용자 수 집계)의 "답변 유도" 배너 재료. 위치 신호 응답에 실려 온
  // 대기 질문이며, **presence_registered == true인 응답에서만** 채워진다 — 현장 인증이
  // 안 된 사용자에게는 그릴 데이터 자체가 존재하지 않는다(빈 목록 → 배너 미노출).
  List<Question> _pendingQuestions = [];

  // 헤더가 접혀 상단 바가 단색(primaryColor)으로 바뀌면 날씨 배지를 숨긴다 —
  // 그 자리는 알림·북마크 액션 아이콘과 폭을 다투는 좁은 툴바이기 때문이다.
  final ScrollController _scrollController = ScrollController();
  bool _appBarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_onTypingTick);
    _scrollController.addListener(_handleScroll);

    _fetchExtraInfo();
    _fetchReports();
    _fetchPushSetting();
    _fetchBookmarkState();
    _fetchLiveStatus();
    _fetchCongestion();
    _fetchWeather();
    _fetchBriefing();
    _sendPresenceSignal();
  }

  // ── 기능 6: 현장 사용자 수 집계의 "위치 신호" ──
  // 상세페이지 진입 시 1회. **전용 API도 전용 타이머도 없다** — 기존 verify-location
  // 호출 그 자체가 신호이고, 서버가 부수효과로 presence 1행을 UPSERT한다(Q1-C·Q4-A).
  //
  // 배경 동작이므로 실패를 화면에 절대 띄우지 않는다. 위치 권한 거부·GPS 사용 불가·
  // 반경 밖은 전부 정상 경로다 — 반경 밖은 서버도 403이 아니라 200 + verified:false /
  // presence_registered:false로 응답한다(P9). 사용자가 누르지도 않은 동작의 실패를
  // 다이얼로그로 알리면, 정상 상황이 오류로 보고된다.
  Future<void> _sendPresenceSignal() async {
    // 위치 신호는 presence 1행을 쓰는 **쓰기**라 비로그인은 401이다(Q5-B·계약 2절).
    // 비로그인 사용자는 현장 인원에 잡히지 않는다 — 알려진 대가이고, GPS 권한 팝업을
    // 띄우고 나서 401로 버리는 것보다 아예 시작하지 않는 편이 낫다.
    if (!AuthService().hasServerIdentity) return;
    try {
      final position = await _locationService.getCurrentPosition();
      final result = await ApiService().verifyLocation(
        widget.spot.contentId,
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      // 반경 밖이면 목록을 비운다. 이때 서버의 pending_questions도 빈 배열이지만,
      // 앱에서도 명시적으로 비워 "현장에 없는 사람에게 답변 버튼이 보이는" 경로를 없앤다.
      // (live_screen.dart의 `verify.presenceRegistered ? ... : []`와 같은 처리 —
      // 답변 후 재신호가 실패하면 이미 답변한 질문이 배너에 남는 문제를 막는다.)
      if (!result.presenceRegistered) {
        setState(() => _pendingQuestions = []);
        return;
      }
      setState(() => _pendingQuestions = result.pendingQuestions);
      // 방금 등록된 내 신호가 "현장 N명"에 반영되도록 상태를 한 번 더 읽는다
      // (initState의 _fetchLiveStatus는 신호보다 먼저 끝난다).
      await _fetchLiveStatus();
    } catch (_) {
      // 신호 실패는 알리지 않는다(위 주석). 현장 인원에 내가 안 잡힐 뿐이다.
    }
  }

  Future<void> _fetchExtraInfo() async {
    final api = ApiService();
    final detail = await api.fetchSpotDetail(widget.spot.contentId);
    final intro = await api.fetchSpotIntro(widget.spot.contentId, widget.spot.category ?? '12');
    if (mounted) {
      setState(() {
        _spotDetail = detail;
        _spotIntro = intro;
      });
    }
  }

  // LIVE 상태창(기능 5·6). 매번 실시간 계산된 값이라 방금 올린 제보·위치 신호가 바로 반영된다.
  //
  // 실패를 _liveStatus = null로만 두면 화면에서 "0건 / 0명"으로 그려진다 — 조회 실패가
  // "아무 일도 없음"으로 둔갑한다. 특히 현장 인원은 0이 정상값이라 둘을 구분할 수 없으면
  // 사람이 화면만 보고는 원인을 알 수 없다. 실패 여부를 따로 들고 다닌다.
  Future<void> _fetchLiveStatus() async {
    if (mounted) setState(() => _liveStatusLoading = true);
    try {
      final status = await ApiService().fetchLiveStatus(widget.spot.contentId);
      if (mounted) {
        setState(() {
          _liveStatus = status;
          _liveStatusError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liveStatus = null;
          _liveStatusError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _liveStatusLoading = false);
    }
  }

  // 방문 집중률 "예측"(기능 9, 한국관광공사). 아래 "오늘의 현장 상황"(실측, reports 기반)과는
  // 성격이 다른 지표라 절대 하나로 합치지 않고 별도 블록으로 나란히 보여준다.
  Future<void> _fetchCongestion() async {
    if (mounted) setState(() => _congestionLoading = true);
    try {
      final info = await ApiService().fetchCongestion(widget.spot.contentId);
      if (mounted) setState(() => _congestionInfo = info);
    } catch (_) {
      if (mounted) setState(() => _congestionInfo = null);
    } finally {
      if (mounted) setState(() => _congestionLoading = false);
    }
  }

  // AI 브리핑(기능 10). _fetchCongestion과 같은 패턴 — 로딩 플래그 + try/catch + finally.
  //
  // 서버는 관광지가 없을 때(404)를 빼면 항상 200을 준다. Gemini 실패·타임아웃·재료 부족은
  // 전부 200 + source(TEMPLATE/NONE)로 오므로 여기 catch에 걸리는 건 네트워크 단절이나
  // 404뿐이다. 그때는 _briefing이 null로 남아 섹션 자체가 사라진다 — 에러 문구를 띄우는
  // 대신 못 그리면 숨기는 쪽이 정직하다(날씨 배지와 같은 정책).
  Future<void> _fetchBriefing() async {
    if (mounted) setState(() => _briefingLoading = true);
    try {
      final briefing = await ApiService().fetchBriefing(widget.spot.contentId);
      if (mounted) {
        setState(() => _briefing = briefing);
        // 타이핑은 "500ms 후 무조건"이 아니라 응답이 실제로 도착한 뒤 시작한다.
        // 캐시 미스 시 생성에 수 초가 걸려서, 예전 트리거는 빈 화면에 커서만 돌았다.
        _startBriefingTyping(briefing.fullBriefing);
      }
    } catch (_) {
      if (mounted) setState(() => _briefing = null);
    } finally {
      if (mounted) setState(() => _briefingLoading = false);
    }
  }

  void _startBriefingTyping(String text) {
    _briefingFullText = text;
    _charIndex = 0;
    _displayedBriefing = '';
    _typingController.repeat();
  }

  // 실시간 날씨. 좌표는 보내지 않는다 — 서버가 content_id로 자체 조회하므로
  // HOT SPOTS 진입(widget.spot.latitude == null)에서도 그대로 동작한다.
  //
  // 날씨는 페이지의 부수 정보라 실패를 조용히 삼킨다(_fetchCongestion과 같은 패턴).
  // 다이얼로그·SnackBar를 띄우지 않고 배지 영역만 사라지며, 나머지 섹션은 정상 렌더링된다.
  // 조회 실패(404/네트워크)는 여기서 null이 되고, Open-Meteo 실패는 200 + available:false로
  // 와서 배지가 '정보 없음' fallback으로 그려진다 — 두 상태가 화면에서 구분된다.
  Future<void> _fetchWeather() async {
    try {
      final weather = await ApiService().fetchWeather(widget.spot.contentId);
      if (mounted) setState(() => _weather = weather);
    } catch (_) {
      if (mounted) setState(() => _weather = null);
    }
  }

  // 조회 실패해도 화면은 살아있어야 하므로(설계 원칙 3) 빈 목록으로 조용히 대체한다.
  Future<void> _fetchReports() async {
    if (mounted) setState(() => _reportsLoading = true);
    try {
      final reports = await ApiService().fetchReports(widget.spot.contentId);
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      if (mounted) setState(() => _reports = []);
    } finally {
      if (mounted) setState(() => _reportsLoading = false);
    }
  }

  // 관광지별 자동 제보 유도 알림(기능 2) on/off 상태. 실패해도 화면은 살아있어야 하므로
  // 조회 실패 시 OFF로 간주한다.
  Future<void> _fetchPushSetting() async {
    // `/api/notifications/settings`도 로그인 필요 목록에 포함된다(계약 2절).
    if (!AuthService().hasServerIdentity) {
      if (mounted) setState(() => _pushEnabled = false);
      return;
    }
    try {
      final setting = await ApiService().fetchNotificationSetting(widget.spot.contentId);
      if (mounted) setState(() => _pushEnabled = setting.pushEnabled);
    } catch (_) {
      if (mounted) setState(() => _pushEnabled = false);
    }
  }

  Future<void> _togglePushSetting() async {
    // 알림 설정 저장도 쓰기다 — 비로그인은 401.
    if (!await ensureLoggedIn(context, actionLabel: '제보 알림 설정')) return;
    if (!mounted) return;
    final next = !(_pushEnabled ?? false);
    setState(() => _pushEnabled = next); // 낙관적 반영
    try {
      await ApiService().setNotificationSetting(widget.spot.contentId, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? '이 관광지 근처에 오면 제보 알림을 보내드릴게요' : '제보 알림을 껐어요', style: const TextStyle(fontFamily: 'Pretendard'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _pushEnabled = !next); // 실패 시 롤백
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 설정을 저장하지 못했어요. 다시 시도해주세요.', style: TextStyle(fontFamily: 'Pretendard'))),
      );
    }
  }

  // 북마크 상태(기능 12). 단건 조회 엔드포인트는 없으므로 내 북마크 목록을 받아
  // 이 관광지의 content_id가 들어 있는지로 판정한다(정책 P-B11).
  // 조회 실패 시 알림 설정과 같은 방침으로 "북마크 안 됨"으로 간주한다 —
  // 화면은 살아있어야 하고, 잘못 눌러도 서버가 멱등이라 데이터가 깨지지 않는다.
  Future<void> _fetchBookmarkState() async {
    // 비로그인이면 `/api/bookmarks`가 401이다(계약 2절) — 호출하지 않는다. 결과는 같지만
    // (북마크 안 됨) 실패할 것이 뻔한 요청을 보내고 예외를 삼키는 경로를 남기지 않는다.
    if (!AuthService().hasServerIdentity) {
      if (mounted) setState(() => _bookmarked = false);
      return;
    }
    try {
      final bookmarks = await ApiService().fetchBookmarks();
      if (mounted) {
        setState(() => _bookmarked =
            bookmarks.any((b) => b.contentId == widget.spot.contentId));
      }
    } catch (_) {
      if (mounted) setState(() => _bookmarked = false);
    }
  }

  // _togglePushSetting과 같은 형태 — 낙관적 반영 → 실패 시 롤백 + SnackBar.
  Future<void> _toggleBookmark() async {
    // 북마크도 쓰기라 로그인 필수다(Q5-C — function.md의 표에는 없던 항목이라 빠뜨리기 쉽다).
    // 낙관적 반영보다 **먼저** 막는다. 순서가 반대면 비로그인 사용자의 아이콘이 잠깐
    // 채워졌다가 401로 되돌아가 깜빡인다.
    if (!await ensureLoggedIn(context, actionLabel: '북마크')) return;
    if (!mounted) return;
    final next = !(_bookmarked ?? false);
    setState(() => _bookmarked = next); // 낙관적 반영
    try {
      if (next) {
        await ApiService().addBookmark(widget.spot.contentId);
      } else {
        await ApiService().removeBookmark(widget.spot.contentId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? '북마크에 저장했어요' : '북마크를 해제했어요', style: const TextStyle(fontFamily: 'Pretendard'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _bookmarked = !next); // 실패 시 롤백
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('북마크를 저장하지 못했어요. 다시 시도해주세요.', style: TextStyle(fontFamily: 'Pretendard'))),
      );
    }
  }

  // 기능 4: 능동적 현장 인증. 자동 알림 설정과 무관하게, 이 화면에서 고른
  // widget.spot.contentId 기준으로만 거리를 검증한다.
  Future<void> _attemptOnsiteVerification() async {
    setState(() => _verifyingOnsite = true);
    try {
      final position = await _locationService.getCurrentPosition();
      final result = await ApiService().verifyLocation(
        widget.spot.contentId,
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      if (result.verified) {
        _showReportModal(context);
      } else {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('현장 인증 실패', style: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.bold)),
            content: Text(result.message, style: const TextStyle(fontFamily: 'Pretendard')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인', style: TextStyle(fontFamily: 'Pretendard'))),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치를 확인하지 못했어요: ${e.toString().replaceFirst('Exception: ', '')}', style: const TextStyle(fontFamily: 'Pretendard'))),
      );
    } finally {
      if (mounted) setState(() => _verifyingOnsite = false);
    }
  }

  void _onTypingTick() {
    if (_charIndex < _briefingFullText.length) {
      setState(() {
        _charIndex++;
        _displayedBriefing = _briefingFullText.substring(0, _charIndex);
      });
    } else {
      _typingController.stop();
    }
  }

  @override
  void dispose() {
    _typingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // SliverAppBar(expandedHeight: 280)가 접히는 지점(= 280 - 툴바 높이)을 지나면
  // 상단 바가 단색으로 바뀐다. 배지가 사라지는 시점을 그 전환과 맞추기 위해
  // 여유 20px을 더 두고 판정한다.
  void _handleScroll() {
    final collapsed = _scrollController.hasClients && _scrollController.offset > (280 - kToolbarHeight - 20);
    if (collapsed != _appBarCollapsed) {
      setState(() => _appBarCollapsed = collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLiveStatusSection(),
                // 기능 6 Q6-A: 현장 인증에 성공한 사용자에게만 답변 대기 질문을 띄운다.
                // 목록이 비어 있으면 위젯이 스스로 SizedBox.shrink()로 접힌다.
                PendingQuestionsBanner(
                  questions: _pendingQuestions,
                  spotName: widget.spot.title,
                  // 답변이 등록되면 신호를 다시 보내 대기 목록을 서버 기준으로 갱신하고
                  // (방금 답한 질문은 답변 0건 조건에서 빠진다) 현장 인원도 새로 읽는다.
                  onAnswered: _sendPresenceSignal,
                ),
                const Divider(height: 1),
                _buildCongestionSection(),
                const Divider(height: 1),
                _buildRealtimeDashboard(),
                const Divider(height: 1),
                _buildAiBriefingSection(),
                const Divider(height: 1),
                _buildOverviewSection(),
                const Divider(height: 1),
                _buildBasicInfoSection(),
                const Divider(height: 1),
                QaSection(spotContentId: widget.spot.contentId, spotName: widget.spot.title),
                const Divider(height: 1),
                _buildReviewSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _verifyingOnsite ? null : _attemptOnsiteVerification,
        backgroundColor: LiveSpotTheme.primaryColor,
        icon: _verifyingOnsite
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
            : const Icon(Icons.bolt, color: Colors.white),
        label: const Text('현장 제보', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── SliverAppBar ──
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: LiveSpotTheme.primaryColor,
      leading: IconButton(
        icon: const CircleAvatar(backgroundColor: Colors.black26, child: Icon(Icons.arrow_back, color: Colors.white, size: 20)),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          tooltip: _pushEnabled == true ? '제보 알림 끄기' : '제보 알림 켜기',
          icon: CircleAvatar(
            backgroundColor: Colors.black26,
            child: Icon(
              _pushEnabled == true ? Icons.notifications_active : Icons.notifications_none,
              color: _pushEnabled == true ? Colors.amberAccent : Colors.white,
              size: 20,
            ),
          ),
          onPressed: _pushEnabled == null ? null : _togglePushSetting,
        ),
        IconButton(
          tooltip: _bookmarked == true ? '북마크 해제' : '북마크에 저장',
          icon: CircleAvatar(
            backgroundColor: Colors.black26,
            child: Icon(
              _bookmarked == true ? Icons.bookmark : Icons.bookmark_border,
              color: _bookmarked == true ? Colors.amberAccent : Colors.white,
              size: 20,
            ),
          ),
          // 상태를 아직 모르는 동안(_bookmarked == null)은 누를 수 없다 —
          // 알림 버튼이 _pushEnabled == null에 대해 하는 것과 같다.
          onPressed: _bookmarked == null ? null : _toggleBookmark,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        // 관광지명과 날씨 배지를 같은 줄(Row)에 두고 배지를 오른쪽 끝에 붙인다.
        // 로딩 중이거나 조회 실패(_weather == null)면 배지 없이 이름만 그린다 —
        // 에러 문구·SnackBar를 띄우지 않는다. available:false는 회색 fallback pill로 그려진다.
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.spot.title,
                overflow: TextOverflow.ellipsis,
                style: LiveSpotTheme.title.copyWith(color: Colors.white, shadows: const [Shadow(color: Colors.black45, blurRadius: 8)]),
              ),
            ),
            if (_weather != null && !_appBarCollapsed) ...[
              const SizedBox(width: 8),
              WeatherBadge(weather: _weather!, onImage: true, compact: true),
            ],
          ],
        ),
        titlePadding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 16),
        background: Stack(
          fit: StackFit.expand,
          children: [
            // resolveImageUrl은 null·빈 문자열을 모두 null로 접어주므로 여기서 한 번만 판정한다.
            resolveImageUrl(widget.spot.imageUrl) != null
                ? Image.network(resolveImageUrl(widget.spot.imageUrl)!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _gradientPlaceholder())
                : _gradientPlaceholder(),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]))),
          ],
        ),
      ),
    );
  }

  Widget _gradientPlaceholder() => Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF1565C0)])),
        child: const Center(child: Icon(Icons.landscape, color: Colors.white38, size: 80)),
      );

  // ── 🔴 LIVE 상태창 ──
  Widget _buildLiveStatusSection() {
    final isLive = _liveStatus?.isLive ?? false;
    final reportCount = _liveStatus?.recentReportCount ?? 0;
    final onsiteCount = _liveStatus?.onsiteUserCount ?? 0;
    // 조회에 실패했으면 숫자를 쓰지 않는다. "0명"으로 적으면 알지도 못하는 사실을 주장하게 된다.
    final failed = _liveStatusError && _liveStatus == null;
    // "최근 활동"은 실제 제보(reports) 상위 3건을 그대로 재사용한다 — 질문/답변(기능 7)은
    // 아직 없으므로 REPORT 종류만 존재한다.
    final recentActivities = _reports.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LIVE 헤더
          Row(
            children: [
              if (isLive) ...[
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF1744), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('LIVE', style: LiveSpotTheme.body.copyWith(color: const Color(0xFFFF1744), fontWeight: FontWeight.w900)),
              ] else
                Text('오프라인', style: LiveSpotTheme.body.copyWith(color: LiveSpotTheme.textSecondary, fontWeight: FontWeight.w600)),
              const Spacer(),
              // 예전에는 여기에 "최근 2시간 기준"이 있었다. 아래 통계 행에 시간창이 다른
              // 값(현장 인원 = 30분)이 합류하면서, 헤더의 한 문장이 두 숫자를 다 대표하는
              // 것처럼 보이게 됐다 — 기준은 칸마다 따로 적고 헤더에서는 뺀다(P15).
              if (_liveStatusLoading)
                Text('불러오는 중...', style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary))
              else if (failed)
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 13, color: Colors.red.shade300),
                    const SizedBox(width: 4),
                    Text('상태를 불러오지 못했어요',
                        style: LiveSpotTheme.label.copyWith(color: Colors.red.shade400)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 통계 행 — 두 칸의 **시간창이 서로 다르다**(제보 2시간 / 현장 30분). 한 줄에
          // 나란히 두되 각 칸에 기준을 명시해 같은 시간창의 값처럼 읽히지 않게 한다(P15).
          // "현장"은 접속자 수가 아니라 "최근 30분 안에 여기서 위치 신호를 보낸 사람 수"다 —
          // "현재 N명"·"실시간 접속"으로 쓰지 않는다(P6).
          Row(
            children: [
              _buildLiveStat(
                Icons.edit_note,
                '제보',
                failed ? '—' : '$reportCount건',
                Colors.green,
                note: '최근 ${AppConstants.liveWindowHours}시간 기준',
              ),
              const SizedBox(width: 10),
              _buildLiveStat(
                Icons.person_pin_circle_outlined,
                '현장',
                failed ? '—' : '$onsiteCount명',
                LiveSpotTheme.primaryColor,
                note: '최근 ${AppConstants.presenceWindowMinutes}분 기준',
                tooltip: failed
                    ? '현장 인원을 불러오지 못했어요.'
                    : '최근 ${AppConstants.presenceWindowMinutes}분 기준 $onsiteCount명이 '
                        '이 관광지에서 위치를 인증했어요. 지금 접속 중인 사람 수가 아닙니다.',
              ),
            ],
          ),
          if (recentActivities.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('최근 활동', style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.w600, color: LiveSpotTheme.textSecondary)),
            const SizedBox(height: 6),
            ...recentActivities.map((r) {
              final summary = '제보: 혼잡도 ${MockDataService.crowdednessLabel(r.crowdednessLevel)}, 대기 ${MockDataService.waitingTimeLabel(r.waitingTime)}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(child: Text(summary, style: LiveSpotTheme.caption.copyWith(color: Colors.grey[700]), overflow: TextOverflow.ellipsis)),
                    Text(Formatters.timeAgo(r.createdAt), style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// LIVE 통계 한 칸. [note]는 그 칸만의 시간창 표기다 — 칸마다 기준이 다르므로
  /// (제보 2시간 / 현장 30분) 헤더가 아니라 여기에 붙인다(P15).
  Widget _buildLiveStat(
    IconData icon,
    String label,
    String value,
    Color color, {
    String? note,
    String? tooltip,
  }) {
    Widget cell = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: LiveSpotTheme.body.copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(label, style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary)),
          if (note != null) ...[
            const SizedBox(height: 2),
            // 9px 유지: 통계 칸 하나(폭 좁음) 안에 값/라벨/note 3줄이 들어가야 해서
            // label(11)보다 작아야 한다 — 의도된 스케일 밖 예외.
            Text(
              note,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: LiveSpotTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
    if (tooltip != null) {
      cell = Tooltip(message: tooltip, child: cell);
    }
    return Expanded(child: cell);
  }

  // ── 📊 방문 집중률 예측 (기능 9, 한국관광공사 TatsCnctrRateService) ──
  // 과거 방문 패턴 기반 "예측" 값이다. 실시간 현재 상황이 아니며, 아래 "오늘의 현장
  // 상황"(실제 제보)과 다를 수 있다는 것 자체가 LiveSpot의 차별점이므로 있는 그대로 보여준다.
  Widget _buildCongestionSection() {
    final info = _congestionInfo;
    final rate = info?.congestionRate;
    final hasRate = rate != null;
    final note = _congestionVsActualNote;

    // 집중률 데이터셋은 관광지명으로만 데이터를 구분해서, 서버가 근처 상위 관광지에
    // 매칭시켜 주는 경우가 있다('덕수궁 대한문' -> '덕수궁'). 그럴 땐 무엇을 기준으로
    // 한 값인지 밝힌다 — 다른 관광지의 값을 이 관광지 값인 척하지 않는다.
    final matchedName = info?.spotName;
    final matchedElsewhere =
        hasRate && matchedName != null && matchedName != widget.spot.title;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('📊 방문 집중률 예측', style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.w600, color: LiveSpotTheme.textSecondary)),
              const Spacer(),
              Text(
                _congestionLoading ? '불러오는 중...' : '한국관광공사 예측',
                style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasRate) ...[
            Row(
              children: [
                // heading(20) 유지: 타이포 스케일 최댓값 초과분은 예외를 두지 않고 스케일
                // 안으로 줄인다(design_brief.md §3-6 결정 — live_screen '라이브' 24→20과 동일 판단).
                Text('${rate.toStringAsFixed(0)}%', style: LiveSpotTheme.heading),
                const SizedBox(width: 8),
                CrowdednessBadge(level: info!.level),
              ],
            ),
            const SizedBox(height: 6),
            Text('과거 방문 패턴으로 예측한 오늘의 값이에요. 지금 이 순간의 실측이 아닙니다.',
                style: LiveSpotTheme.caption.copyWith(color: LiveSpotTheme.textSecondary)),
            if (matchedElsewhere) ...[
              const SizedBox(height: 4),
              Text("'$matchedName' 기준 예측값이에요.",
                  style: LiveSpotTheme.label.copyWith(color: Colors.orange[700])),
            ],
          ] else if (!_congestionLoading) ...[
            Text('예측 대상 아님', style: LiveSpotTheme.body.copyWith(fontWeight: FontWeight.w600, color: LiveSpotTheme.textSecondary)),
            const SizedBox(height: 4),
            Text('집중률 예측은 주요 관광지를 대상으로 제공돼요.',
                style: LiveSpotTheme.caption.copyWith(color: LiveSpotTheme.textSecondary, height: 1.4)),
          ],
          if (note != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
              child: Text(note, style: LiveSpotTheme.caption.copyWith(color: Colors.blue[800], height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }

  /// 예측 등급과 실측(오늘의 현장 상황) 등급이 둘 다 있고 서로 다를 때만 안내문을 만든다.
  /// 같으면 굳이 중복으로 말하지 않는다.
  String? get _congestionVsActualNote {
    final predictedLevel = _congestionInfo?.level; // green / yellow / red
    final actualCode = _liveStatus?.currentCrowdedness; // EASY / NORMAL / BUSY
    if (predictedLevel == null || predictedLevel == 'unknown' || actualCode == null) return null;

    const actualToLevel = {'EASY': 'green', 'NORMAL': 'yellow', 'BUSY': 'red'};
    final actualLevel = actualToLevel[actualCode];
    if (actualLevel == null || actualLevel == predictedLevel) return null;

    const predLabel = {'green': '여유', 'yellow': '보통', 'red': '높음'};
    const actLabel = {'green': '여유', 'yellow': '보통', 'red': '혼잡'};
    return '예상 방문 집중도는 ${predLabel[predictedLevel]} 수준이지만, 현재 현장 제보는 ${actLabel[actualLevel]} 상태입니다.';
  }

  // ── 실시간 대시보드 ──
  // 혼잡도/대기시간/주차는 "당일(오늘, KST 기준)" 제보로만 갱신된다 — 정보 신선도가
  // 중요해서, 오늘 제보가 없으면 어제 이전 값을 이어 보여주지 않고 "오늘 정보 없음"으로 표시한다.
  Widget _buildRealtimeDashboard() {
    final crowdCode = _liveStatus?.currentCrowdedness;
    final waitCode = _liveStatus?.currentWaitingTime;
    final parkCode = _liveStatus?.currentParkingStatus;
    const noInfoToday = '오늘 정보 없음';
    final crowd = crowdCode == null ? noInfoToday : MockDataService.crowdednessLabel(crowdCode);
    final wait = waitCode == null ? noInfoToday : MockDataService.waitingTimeLabel(waitCode);
    final park = parkCode == null ? noInfoToday : MockDataService.parkingLabel(parkCode);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('오늘의 현장 상황', style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.w600, color: LiveSpotTheme.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDashItem(Icons.people_alt_rounded, '혼잡도', crowd, crowdCode == null ? LiveSpotTheme.textSecondary : _crowdColor(crowdCode)),
              const SizedBox(width: 10),
              _buildDashItem(Icons.access_time_rounded, '대기시간', wait, waitCode == null ? LiveSpotTheme.textSecondary : LiveSpotTheme.primaryColor),
              const SizedBox(width: 10),
              _buildDashItem(Icons.local_parking_rounded, '주차', park, parkCode == null ? LiveSpotTheme.textSecondary : _crowdColor(parkCode)),
            ],
          ),
        ],
      ),
    );
  }

  Color _crowdColor(String code) => code == 'EASY'
      ? LiveSpotTheme.successColor
      : code == 'NORMAL'
          ? LiveSpotTheme.warningColor
          : LiveSpotTheme.dangerColor;

  Widget _buildDashItem(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary)),
            const SizedBox(height: 2),
            Text(value, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  // ── AI 브리핑 (기능 10) ──
  // 상태는 셋뿐이다: 로딩(스켈레톤) / 정상(타이핑 본문) / 실패(섹션 자체를 숨김).
  // 서버가 실패해도 200 + TEMPLATE·NONE으로 오므로 "AI가 실패했어요" 같은 화면은 없다.
  Widget _buildAiBriefingSection() {
    final briefing = _briefing;

    // 네트워크 단절·404로 아예 못 받은 경우. 빈 카드나 에러 문구를 남기지 않고 통째로
    // 비운다 — 못 그리면 숨기는 쪽이 정직하다(WeatherBadge와 같은 정책).
    if (!_briefingLoading && briefing == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF7C4DFF)]), borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text('AI 브리핑', style: LiveSpotTheme.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                ]),
              ),
              const Spacer(),
              // ⚠️ 이 라벨은 **실제로 Gemini가 문장을 쓴 경우에만** 붙는다.
              // source=TEMPLATE(서버가 재료만 이어 붙임)·NONE(AI 호출 안 함)에는 절대
              // 붙이지 않는다. 예전에는 여기가 하드코딩이라 템플릿 문장에도 AI 라벨이
              // 붙어 있었다 — 없는 근거를 주장하는 상태였다.
              // 판정은 Briefing.isAiGenerated 하나로 모으고, 모르는 source 값은 false다.
              if (briefing != null && briefing.isAiGenerated)
                Text('Gemini로 생성됨', style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          if (briefing == null)
            _buildBriefingSkeleton()
          else
            Text(_displayedBriefing, style: LiveSpotTheme.body.copyWith(height: 1.6, color: Colors.grey[700])),
        ],
      ),
    );
  }

  /// 응답 도착 전 자리를 잡아두는 회색 바 3줄. 캐시 미스 시 생성에 수 초가 걸려서,
  /// 이게 없으면 섹션이 갑자기 나타났다 사라지는 것처럼 보인다.
  Widget _buildBriefingSkeleton() {
    Widget bar(double widthFactor) => FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 12,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(1.0), bar(0.95), bar(0.6)],
    );
  }

  // ── 개요 (공식 정보) ──
  // KTO API 원문은 <br> 등 HTML 태그와 엔티티(&amp; 등)를 자주 포함한다 — 사용자에게
  // 그대로 노출하지 않고 <br>은 줄바꿈으로, 나머지 태그/엔티티는 걷어낸다.
  Widget _buildOverviewSection() {
    if (_spotDetail?['overview'] == null || _spotDetail!['overview'].toString().isEmpty) {
      return const SizedBox.shrink();
    }
    final rawText = _spotDetail!['overview'].toString();
    final cleanText = _cleanOverviewText(rawText);
    final textStyle = LiveSpotTheme.body.copyWith(height: 1.6, color: Colors.grey[700]);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('관광지 소개', style: LiveSpotTheme.title.copyWith(color: Colors.grey[800])),
          const SizedBox(height: 8),
          // 기본 5줄까지만 보여주고, 5줄을 넘칠 때만 더보기/접기를 노출한다.
          // TextPainter로 실제 렌더 폭 기준 줄바꿈 여부를 재서 넘치는지 판단한다 —
          // 문자 수로 어림하면 폭이 넓은 문자·좁은 폭에서 어긋난다.
          LayoutBuilder(
            builder: (context, constraints) {
              final tp = TextPainter(
                text: TextSpan(text: cleanText, style: textStyle),
                maxLines: 5,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: constraints.maxWidth);
              final overflows = tp.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cleanText,
                    style: textStyle,
                    maxLines: _overviewExpanded ? null : 5,
                    overflow: _overviewExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                  if (overflows) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
                      child: Text(
                        _overviewExpanded ? '접기' : '더보기',
                        style: LiveSpotTheme.body.copyWith(fontWeight: FontWeight.w600, color: LiveSpotTheme.primaryColor),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _cleanOverviewText(String raw) {
    var text = raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': "'",
      '&#39;': "'",
      '&nbsp;': ' ',
    };
    entities.forEach((entity, replacement) {
      text = text.replaceAll(entity, replacement);
    });
    text = text.replaceAll(RegExp(r'&[a-zA-Z0-9#]+;'), '');
    return text.trim();
  }

  // ── 기본 정보 ──
  Widget _buildBasicInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('기본 정보', style: LiveSpotTheme.title.copyWith(color: Colors.grey[800])),
          const SizedBox(height: 12),
          _infoRow(Icons.location_on_outlined, '주소', widget.spot.address ?? '정보 없음'),
          if (_spotDetail?['tel'] != null && _spotDetail!['tel']!.toString().isNotEmpty)
            _infoRow(Icons.phone_outlined, '전화', _spotDetail!['tel']),
          if (_spotIntro?['use_time'] != null && _spotIntro!['use_time']!.toString().isNotEmpty)
            _infoRow(Icons.access_time_outlined, '운영 시간', _spotIntro!['use_time']),
          if (_spotIntro?['use_fee'] != null && _spotIntro!['use_fee']!.toString().isNotEmpty)
            _infoRow(Icons.attach_money_outlined, '이용 요금', _spotIntro!['use_fee']),
          if (_spotIntro?['parking'] != null && _spotIntro!['parking']!.toString().isNotEmpty)
            _infoRow(Icons.local_parking_outlined, '주차 여부', _spotIntro!['parking']),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _hasCoordinates ? _openKakaoMap : null,
              icon: const Icon(Icons.directions),
              label: const Text('카카오맵으로 길찾기'),
              style: OutlinedButton.styleFrom(foregroundColor: LiveSpotTheme.primaryColor, side: const BorderSide(color: LiveSpotTheme.primaryColor), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
          if (!_hasCoordinates) ...[
            const SizedBox(height: 8),
            Text(
              '이 장소는 좌표 정보가 없어 길찾기를 지원하지 않아요.',
              style: LiveSpotTheme.caption.copyWith(color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  // 위도·경도가 없는 관광지(TourAPI 원본 데이터 누락)에서는 버튼을 비활성화한다 —
  // URL이 "이름,null,null"로 만들어져 카카오맵이 오류 페이지를 띄우는 것을 막는다.
  bool get _hasCoordinates => widget.spot.latitude != null && widget.spot.longitude != null;

  // SDK 연동 없이 카카오맵 웹 링크 규격(map.kakao.com/link/map/이름,위도,경도)만 사용한다.
  Future<void> _openKakaoMap() async {
    if (!_hasCoordinates) return;
    final uri = Uri.parse(
      'https://map.kakao.com/link/map/'
      '${Uri.encodeComponent(widget.spot.title)},${widget.spot.latitude},${widget.spot.longitude}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오맵을 열지 못했어요.', style: TextStyle(fontFamily: 'Pretendard'))),
      );
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    // TourAPI 원문에는 use_time·use_fee·parking처럼 <br> 태그가 섞여 오는 필드가 있다.
    // "관광지 소개"와 같은 정리 함수를 그대로 써서 실제 줄바꿈으로 바꾼다.
    final cleaned = _cleanOverviewText(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 8),
          SizedBox(width: 60, child: Text(label, style: LiveSpotTheme.body.copyWith(color: LiveSpotTheme.textSecondary))),
          Expanded(child: Text(cleaned, style: LiveSpotTheme.body.copyWith(color: Colors.grey[800]))),
        ],
      ),
    );
  }

  // ── 리뷰 섹션 ──
  Widget _buildReviewSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📝 현장 제보', style: LiveSpotTheme.title.copyWith(color: Colors.grey[800])),
          const SizedBox(height: 8),
          if (_reportsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_reports.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text('아직 제보가 없어요.\n첫 번째 현장 제보를 남겨보세요!', textAlign: TextAlign.center, style: LiveSpotTheme.body.copyWith(color: LiveSpotTheme.textSecondary))),
            )
          else
            ..._reports.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // 10px 유지: 24px 아바타 원 안에 들어가는 이니셜 한 글자라 label(11)보다
                          // 작아야 한다 — 의도된 스케일 밖 예외(다른 작은 배지들과 같은 이유).
                          CircleAvatar(radius: 12, backgroundColor: LiveSpotTheme.primaryColor.withOpacity(0.2), child: Text(r.userNickname.substring(0, 1), style: const TextStyle(fontSize: 10, color: LiveSpotTheme.primaryColor, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 6),
                          Text(r.userNickname, style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          if (r.gpsVerified) const GpsVerifiedBadge(),
                          const Spacer(),
                          Text(Formatters.reportRecency(r.createdAt), style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _chipBadge('혼잡도: ${MockDataService.crowdednessLabel(r.crowdednessLevel)}', _crowdColor(r.crowdednessLevel)),
                          _chipBadge('대기: ${MockDataService.waitingTimeLabel(r.waitingTime)}', LiveSpotTheme.primaryColor),
                          if (r.parkingStatus != null) _chipBadge('주차: ${MockDataService.parkingLabel(r.parkingStatus!)}', _crowdColor(r.parkingStatus!)),
                        ],
                      ),
                      if (r.comment != null) ...[
                        const SizedBox(height: 4),
                        Text(r.comment!, style: LiveSpotTheme.body.copyWith(color: Colors.grey[700])),
                      ],
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _chipBadge(String text, Color color) {
    // 10px 유지: 세로 패딩 2인 초소형 칩이라 label(11)보다 작아야 한다 — 다른 배지
    // 예외들과 같은 이유(design_brief.md §3-6).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── 제보 모달 ──
  void _showReportModal(BuildContext context) async {
    // 제보는 로그인 필수(Q5-C·AC2). 버튼을 숨기지 않고 눌리게 두되 유도 시트로 보낸다.
    if (!await ensureLoggedIn(context, actionLabel: '현장 제보')) return;
    if (!context.mounted) return;
    final result = await showModalBottomSheet<Report>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => QuickReportModal(
        spotName: widget.spot.title,
        spotContentId: widget.spot.contentId,
      ),
    );
    if (result != null) {
      _fetchReports();
      _fetchLiveStatus();
    }
  }
}
