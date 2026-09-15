import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../models/spot.dart';
import '../../models/hotspot_entry.dart';
import '../../models/my_report_entry.dart';
import '../../models/my_answer_entry.dart';
import '../../utils/formatters.dart';
import '../../utils/image_url.dart';
import '../../widgets/quick_report_modal.dart';
import '../../widgets/qa_section.dart';
import '../../widgets/global_qa_list.dart';
import '../../widgets/gps_verified_badge.dart';
import '../../widgets/login_required_sheet.dart';
import '../detail/spot_detail_screen.dart';

enum _GpsMatchStatus { idle, loading, matched, none, error, selecting }

/// Live 페이지. 구조는 정책에 따라 고정된다.
///   GPS OFF                 : HOT SPOTS → 전체 LIVE Q&A
///   GPS ON + 현장 인증 성공  : 내 현장 Q&A → HOT SPOTS → 전체 LIVE Q&A
/// 개별 현장 제보 목록(코멘트 스트림)은 Live 메인에서 노출하지 않는다 — 제보 원문은
/// 관광지 상세페이지에서 계속 확인할 수 있다(데이터는 DB에 그대로 저장됨).
class LiveScreen extends StatefulWidget {
  /// 이 탭이 지금 화면에 보이는지. `HomeScreen`의 IndexedStack이 탭을 살려두기 때문에
  /// initState는 앱 실행 중 한 번만 돈다 — 그 사이 들어온 실제 제보를 핫스팟 랭킹에
  /// 반영하려면 탭이 다시 보이는 시점을 알아야 한다(MapScreen·ProfileScreen과 같은 규약).
  final bool isActive;

  const LiveScreen({super.key, this.isActive = true});

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
  // 근처 후보가 여럿이고 내 최근 활동과도 겹치지 않을 때(_GpsMatchStatus.selecting)
  // 사용자가 직접 고를 수 있도록 보여주는 목록.
  List<Spot> _gpsCandidates = [];

  // ── 기능 6(현장 사용자 수 집계) ──
  // 아래 3분 타이머의 verify-location 호출이 곧 위치 신호다(Q1-C). 신규 API도 신규
  // 타이머도 없다 — 여기서 하는 일은 "이미 보내고 있던 신호"의 응답을 화면에 쓰는 것뿐.
  //
  // null = 아직 못 읽었거나 조회에 실패함 → 표기를 아예 숨긴다.
  // 0    = 서버가 "최근 30분 안에 아무도 없었다"고 답한 값 → "0명"으로 그린다.
  // 이 둘을 뭉개면 조회 실패가 "0명"으로 보인다.
  int? _onsiteUserCount;

  // 2026-09-13(015): 답변 대기 질문 배너(`PendingQuestionsBanner`)를 이 화면에서 제거했다.
  // 그 배너가 그리던 집합은 바로 아래 QaSection(activeOnly: true)의 부분집합이라
  // (배너 = fetch_spot_questions(pending_only, active_only, limit N) ⊂ QaSection의
  // active_only 전체) 정보 손실 없이 중복만 걷어낸 것이다. 그래서 배너에 넘기던
  // `_pendingQuestions` 필드도 함께 지웠다 — 남기면 죽은 코드가 된다.
  //
  // ⚠️ 위젯 파일(`widgets/pending_questions_banner.dart`)과 서버 응답 필드
  // (`verify-location`의 `pending_questions`)는 **그대로 살아 있다.**
  // `spot_detail_screen.dart`가 계속 쓴다.

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

  @override
  void didUpdateWidget(covariant LiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // LIVE 탭이 지금 막 보이게 됨 — 숨어 있는 동안 다른 사용자의 제보가 들어왔을 수
    // 있으므로 핫스팟 랭킹을 다시 조회한다.
    if (widget.isActive && !oldWidget.isActive) {
      setState(() {
        _hotspotsFuture = _apiService.fetchHotspots();
      });
    }
  }

  Future<void> _onToggleGps(bool value) async {
    // 현장 인증은 로그인 필수다 — 이 토글을 켜면 `verify-location`(POST) ·
    // `/reports/me` · `/questions/me/answers` 세 개가 나가고 비로그인은 전부 401이다(AC2).
    // 게이트가 없으면 그 401이 `_GpsMatchStatus.error`의 빨간 문구로 보여서, 로그인
    // 유도 시트(Q5-C)가 뜨지 않는다(QA 1회차 F1).
    //
    // **GPS 권한 요청보다 먼저 막는다**(01_spec 1-4절, `:269`의 제보 FAB와 같은 순서).
    // 순서가 반대면 어차피 못 쓸 사용자에게 위치 권한부터 요구하게 된다.
    //
    // 켜는 방향만 막는다. 끄는 동작까지 막으면 로그인이 풀린 뒤 토글을 되돌릴 수 없다.
    if (value && !await ensureLoggedIn(context, actionLabel: '현장 인증')) return;
    if (!mounted) return;

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
        _gpsCandidates = [];
        _onsiteUserCount = null;
      });
    }
  }

  // GPS 연동: 현재 위치에서 실제로 100m+오차(150m) 이내로 인증되는 관광지가 있을 때만
  // "내 현장 Q&A"를 노출한다. 여러 관광지가 주변에 있으면 임의로 아무거나 고르지 않는다.
  // 후보가 하나뿐이면 모호함이 없으니 바로 서버 인증(verify-location)으로 넘기고,
  // 여럿이면 내 최근 제보·답변 이력과 겹치는 곳이 있는지 먼저 보고, 그마저 없으면
  // 사용자가 직접 고르게 한다(_GpsMatchStatus.selecting).
  Future<void> _refreshGpsMatch({bool silent = false}) async {
    if (!silent && mounted) setState(() => _gpsMatchStatus = _GpsMatchStatus.loading);
    try {
      final position = await _locationService.getCurrentPosition();
      final nearby = await _apiService.fetchNearbySpots(position.latitude, position.longitude, radius: 500);
      if (nearby.isEmpty) {
        if (mounted) {
          setState(() {
            _gpsMatchStatus = _GpsMatchStatus.none;
            _gpsCandidates = [];
            _onsiteUserCount = null;
          });
        }
        return;
      }
      if (nearby.length == 1) {
        await _verifyCandidate(nearby.first, position);
        return;
      }
      final matched = await _matchByRecentActivity(nearby);
      if (matched != null) {
        await _verifyCandidate(matched, position);
        return;
      }
      if (!mounted) return;
      setState(() {
        _gpsMatchStatus = _GpsMatchStatus.selecting;
        _gpsCandidates = nearby;
        _gpsMatchedSpot = null;
        _onsiteUserCount = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsMatchStatus = _GpsMatchStatus.error;
        _gpsMatchedSpot = null;
        _gpsCandidates = [];
        _onsiteUserCount = null;
        _gpsMatchError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // 근처 후보 중 내가 최근에 제보했거나 질문에 답변한 관광지가 있으면 그곳으로
  // 특정한다 — 앱이 위치를 스스로 판정하는 게 아니라 "어느 후보로 인증을 시도할지"만
  // 좁히는 것이고, 실제 인증은 뒤이은 verify-location이 그대로 담당한다.
  // 조회 실패는 "이력 없음"과 동일하게 취급해 사용자가 직접 고르는 안전한 쪽으로 넘긴다.
  Future<Spot?> _matchByRecentActivity(List<Spot> candidates) async {
    final candidateIds = candidates.map((s) => s.contentId).toSet();
    DateTime? bestTime;
    String? bestId;
    try {
      final reports = await _apiService.fetchMyReports();
      final answers = await _apiService.fetchMyAnswers();
      for (final MyReportEntry report in reports) {
        if (!candidateIds.contains(report.spotContentId)) continue;
        if (bestTime == null || report.createdAt.isAfter(bestTime)) {
          bestTime = report.createdAt;
          bestId = report.spotContentId;
        }
      }
      for (final MyAnswerEntry answer in answers) {
        if (!candidateIds.contains(answer.spotContentId)) continue;
        if (bestTime == null || answer.createdAt.isAfter(bestTime)) {
          bestTime = answer.createdAt;
          bestId = answer.spotContentId;
        }
      }
    } catch (_) {
      return null;
    }
    if (bestId == null) return null;
    return candidates.firstWhere((s) => s.contentId == bestId);
  }

  // 확정된 후보 하나에 대해 서버 인증(verify-location)을 시도한다. 이 호출이 곧
  // 위치 신호다 — 서버가 반경 판정을 통과시키면 presence를 갱신하고 답변 대기
  // 질문을 함께 실어 보낸다(기능 6, Q1-C).
  Future<void> _verifyCandidate(Spot candidate, Position position) async {
    try {
      final verify = await _apiService.verifyLocation(candidate.contentId, position.latitude, position.longitude);
      if (!mounted) return;
      if (verify.verified) {
        setState(() {
          _gpsMatchStatus = _GpsMatchStatus.matched;
          _gpsMatchedSpot = candidate;
          _gpsCandidates = [];
        });
        await _fetchOnsiteCount(candidate.contentId);
      } else {
        setState(() {
          _gpsMatchStatus = _GpsMatchStatus.none;
          _gpsMatchedSpot = null;
          _gpsCandidates = [];
          _onsiteUserCount = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsMatchStatus = _GpsMatchStatus.error;
        _gpsMatchedSpot = null;
        _gpsCandidates = [];
        _onsiteUserCount = null;
        _gpsMatchError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // 사용자가 선택 목록에서 후보 하나를 직접 골랐을 때. 목록을 보여준 시점과 탭한
  // 시점 사이에 위치가 바뀔 수 있으니 위치를 다시 읽은 뒤 인증을 시도한다.
  Future<void> _onSelectGpsCandidate(Spot candidate) async {
    if (mounted) setState(() => _gpsMatchStatus = _GpsMatchStatus.loading);
    try {
      final position = await _locationService.getCurrentPosition();
      await _verifyCandidate(candidate, position);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsMatchStatus = _GpsMatchStatus.error;
        _gpsCandidates = [];
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
    // 제보는 로그인 필수(Q5-C·AC2). 버튼은 숨기지 않고 눌리게 두되 여기서 유도 시트를
    // 띄운다 — 위치 조회(GPS 권한 팝업)보다 **먼저** 막는다. 순서가 반대면 결국 로그인
    // 시트를 보게 될 사용자에게 GPS 권한부터 요구하게 된다.
    if (!await ensureLoggedIn(context, actionLabel: '현장 제보')) return;
    if (!context.mounted) return;
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
        label: const Text('실시간 제보', style: TextStyle(color: Colors.white, fontFamily: 'Pretendard', fontWeight: FontWeight.bold)),
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
                'Livespot',
                style: LiveSpotTheme.heading,
              ),
              const Spacer(),
              Row(
                children: [
                  Text('GPS 연동', style: LiveSpotTheme.caption.copyWith(color: LiveSpotTheme.textSecondary, fontWeight: FontWeight.bold)),
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
          Text(
            '실시간 현황',
            style: LiveSpotTheme.body.copyWith(color: LiveSpotTheme.textSecondary),
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
                      Text('📍 내 현장 · ',
                          style: LiveSpotTheme.body.copyWith(fontWeight: FontWeight.bold, color: LiveSpotTheme.primaryColor)),
                      Expanded(
                        child: Text(spot.title,
                            overflow: TextOverflow.ellipsis,
                            style: LiveSpotTheme.body.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      const GpsVerifiedBadge(),
                    ],
                  ),
                  _buildOnsiteCountLine(),
                ],
              ),
            ),
            // 2026-09-13(015): 여기 있던 답변 대기 질문 배너를 제거했다. 바로 아래
            // QaSection이 같은 질문들을 이미 보여주고 있어(배너 집합 ⊂ QaSection 집합)
            // 같은 화면에 같은 질문이 두 번 나오던 중복이었다. 이 자리에 배너를 다시
            // 넣지 말 것.
            //
            // 기능 8의 알림 다이얼로그는 이 화면 안에 있지 않다 — `app.dart`의
            // MaterialApp.builder가 Navigator 위에 모달로 띄운다.
            QaSection(spotContentId: spot.contentId, spotName: spot.title, showAskButton: false, activeOnly: true),
          ],
        );
      case _GpsMatchStatus.loading:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 10),
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
      case _GpsMatchStatus.selecting:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 10),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '근처에 관광지가 여러 곳 있어요. 지금 계신 곳을 골라주세요.',
                style: LiveSpotTheme.body.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._gpsCandidates.map((spot) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => _onSelectGpsCandidate(spot),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              spot.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                          ),
                          if (spot.dist != null)
                            Text(
                              '${spot.dist!.round()}m',
                              style: LiveSpotTheme.caption.copyWith(color: LiveSpotTheme.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        );
      case _GpsMatchStatus.none:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              Icon(Icons.location_off, color: Colors.grey.shade400),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '인증된 관광지가 없어요.\n관광지 반경 150m 이내로 이동한 뒤 다시 시도해보세요.',
                  style: LiveSpotTheme.body,
                ),
              ),
            ],
          ),
        );
      case _GpsMatchStatus.error:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.shade100)),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade300),
              const SizedBox(width: 12),
              Expanded(
                child: Text('위치를 확인하지 못했어요: ${_gpsMatchError ?? ''}', style: LiveSpotTheme.body),
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
            style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.bold, color: Colors.grey[800]),
          ),
          const SizedBox(width: 6),
          Text(
            '· 최근 ${AppConstants.presenceWindowMinutes}분 기준',
            style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary),
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
          padding: EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 10),
          child: Text('🔥 HOT SPOTS', style: LiveSpotTheme.title),
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
                margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 6),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade300),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'HOT SPOTS를 불러오지 못했어요: ${snapshot.error.toString().replaceFirst('Exception: ', '')}',
                        style: LiveSpotTheme.body,
                      ),
                    ),
                  ],
                ),
              );
            }
            final hotspots = snapshot.data ?? [];
            if (hotspots.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 6),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('지금 활동 중인 관광지가 없어요', style: LiveSpotTheme.body.copyWith(color: LiveSpotTheme.textSecondary))),
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
                  margin: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding, vertical: 6),
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
                    subtitle: Text(_hotspotSubtitle(spot), style: LiveSpotTheme.caption.copyWith(color: LiveSpotTheme.textSecondary)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                      // 10px 유지: 작은 색상 배지 안 라벨(예: "혼잡")은 label(11) 스케일보다
                      // 작아야 배지 형태(폭 좁은 캡슐)가 안 깨진다 — 의도된 스케일 밖 예외.
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

  Color _levelColor(String level) => level == 'EASY'
      ? LiveSpotTheme.successColor
      : level == 'NORMAL'
          ? LiveSpotTheme.warningColor
          : LiveSpotTheme.dangerColor;

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
              // 9px 유지: 18x18 원 안에 두 자리 순위까지 들어가야 해서 label(11)보다
              // 작아야 한다 — 의도된 스케일 밖 예외(위 배지 라벨과 같은 이유).
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
