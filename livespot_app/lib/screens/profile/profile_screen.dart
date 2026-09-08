import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../models/activity_counts.dart';
import '../../models/credit_summary.dart';
import '../../services/api_service.dart';
import '../../widgets/credit_badge.dart';
import 'bookmarks_screen.dart';
import 'credit_ledger_screen.dart';
import 'my_qna_screen.dart';
import 'my_reports_screen.dart';

/// 스탯 행 하나를 채우는 데 필요한 두 응답을 묶은 것.
///
/// 굳이 합쳐서 한 번에 기다리는 이유: 두 엔드포인트가 같은 서버의 같은 라우터라
/// 실패하면 어차피 함께 실패한다. 따로 두면 에러 배너가 두 개 뜨고 스켈레톤이
/// 따로 논다. 대신 어느 쪽이 실패했는지는 ApiService의 예외 메시지에 남는다.
class _MyStats {
  final CreditSummary credit;
  final ActivityCounts activity;

  _MyStats(this.credit, this.activity);
}

class ProfileScreen extends StatefulWidget {
  /// 이 탭이 지금 화면에 보이는지. `HomeScreen`의 IndexedStack이 탭을 살려두기 때문에
  /// initState는 앱 실행 중 한 번만 돈다 — 그 사이 제보·답변으로 오른 크레딧을
  /// 반영하려면 탭이 다시 보이는 시점을 알아야 한다(MapScreen과 같은 규약).
  final bool isActive;

  const ProfileScreen({super.key, this.isActive = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _prefsKey = 'dev_test_user_id';

  List<Map<String, dynamic>> _testUsers = [];
  String? _selectedTestUserId;
  bool _loadingTestUsers = false;

  // build 안에서 만들면 리빌드마다 재호출된다. initState에서 한 번만 만들고,
  // 테스트유저를 바꾸거나 내역 화면에서 돌아왔을 때만 다시 만든다.
  late Future<_MyStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    if (kDebugMode) _loadTestUsers();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 마이 탭이 지금 막 보이게 됨 — 숨어 있는 동안 제보·답변으로 크레딧이 올랐을 수
    // 있다. 적립은 제보/답변 응답에 드러나지 않아(백엔드 계약 4절) 다시 묻는 수밖에 없다.
    if (widget.isActive && !oldWidget.isActive) {
      // 이미 이 프레임에서 리빌드가 진행 중이라 setState는 불필요하다.
      _statsFuture = _loadStats();
    }
  }

  Future<_MyStats> _loadStats() async {
    final results = await Future.wait([
      ApiService().fetchMyCredit(),
      ApiService().fetchMyActivity(),
    ]);
    return _MyStats(results[0] as CreditSummary, results[1] as ActivityCounts);
  }

  void _reloadStats() {
    setState(() => _statsFuture = _loadStats());
  }

  Future<void> _loadTestUsers() async {
    setState(() => _loadingTestUsers = true);
    try {
      final users = await ApiService().fetchTestUsers();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) ApiService.testUserId = saved;
      if (mounted) {
        setState(() {
          _testUsers = users;
          _selectedTestUserId = saved ?? ApiService.testUserId;
        });
        // 저장된 테스트유저를 복원했다면 그 사람 기준으로 크레딧을 다시 읽는다.
        // (initState의 첫 조회는 헤더가 붙기 전에 나갔을 수 있다.)
        if (saved != null) _reloadStats();
      }
    } finally {
      if (mounted) setState(() => _loadingTestUsers = false);
    }
  }

  Future<void> _onSelectTestUser(String? userId) async {
    if (userId == null) return;
    setState(() => _selectedTestUserId = userId);
    ApiService.testUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, userId);
    if (!mounted) return;
    // 크레딧은 사용자별로 갈린다 — 전환했으면 반드시 다시 읽는다.
    // (로그인이 없는 지금, 사용자별 분리를 시연하는 수단이 이 드롭다운이다.)
    _reloadStats();
    final nickname = _testUsers.firstWhere((u) => u['id'] == userId, orElse: () => {'nickname': userId})['nickname'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('테스트 유저 전환: $nickname', style: const TextStyle(fontFamily: 'Pretendard'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildProfileCard(),
              const SizedBox(height: 16),
              _buildStatsSection(),
              if (kDebugMode && (_testUsers.isNotEmpty || _loadingTestUsers)) ...[
                const SizedBox(height: 16),
                _buildTestUserSwitcher(),
              ],
              const SizedBox(height: 16),
              _buildMenuSection(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // 개발/QA 전용: 서버 TEST_MODE=true일 때만 목록이 채워진다. 여러 seed_user_*로
  // 제보 상황을 시뮬레이션할 수 있도록 프로필 화면에서 바로 전환한다.
  Widget _buildTestUserSwitcher() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 6),
              Text('테스트 모드: 테스트유저 전환', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900)),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingTestUsers)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedTestUserId,
              hint: const Text('기본 test_user 사용 중'),
              items: _testUsers
                  .map((u) => DropdownMenuItem<String>(
                        value: u['id'] as String,
                        child: Text(u['nickname'] as String),
                      ))
                  .toList(),
              onChanged: _onSelectTestUser,
            ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF1565C0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1E88E5).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2), border: Border.all(color: Colors.white38, width: 2)),
                child: const Center(child: Icon(Icons.person, color: Colors.white, size: 30)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('로그인하세요', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('로그인하고 현장 제보를 시작하세요!', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 로그인 수단은 카카오 하나만이다(function.md:76). 동작하지 않던 Google 버튼은
          // 설계와 어긋나는 껍데기라 제거했다. 카카오 버튼의 연결은 로그인 단계(9단계)에서 한다.
          Row(children: [
            Expanded(child: _buildLoginButton('카카오 로그인', const Color(0xFFFEE500), Colors.black87, () {})),
          ]),
        ],
      ),
    );
  }

  Widget _buildLoginButton(String text, Color bgColor, Color textColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(text, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600))),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 스탯 행 — 제보 / 답변 / Credit / 뱃지
  //
  // 여기 숫자는 전부 서버 값이다. 예전의 하드코딩 '0'·'0p'로 되돌리지 말 것(P25):
  // 조회가 실패했는데 0이 보이면 "활동이 없는 사람"과 구분되지 않는다.
  // 그래서 로딩 중에는 스켈레톤, 실패 시에는 '-' + 에러 배너다(P26).
  // ---------------------------------------------------------------------------

  Widget _buildStatsSection() {
    return FutureBuilder<_MyStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        final bool loading = snapshot.connectionState == ConnectionState.waiting;
        final bool failed = snapshot.hasError;
        final _MyStats? stats = failed ? null : snapshot.data;

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              // 뱃지 칸은 라벨 길이에 따라 폭이 변한다('새싹' vs 'Spot 탐방객').
              // 네 칸을 Expanded로 균등 분배해 좁은 화면에서 RenderFlex 오버플로가
              // 나지 않게 하고, 넘치는 라벨은 pill 안에서 ellipsis로 잘리게 한다.
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      stats == null ? null : '${stats.activity.reportCount}',
                      '제보',
                      Icons.edit_note,
                      loading: loading,
                    ),
                  ),
                  _buildDivider(),
                  Expanded(
                    child: _buildStatItem(
                      stats == null ? null : '${stats.activity.answerCount}',
                      '답변',
                      Icons.question_answer_outlined,
                      loading: loading,
                    ),
                  ),
                  _buildDivider(),
                  Expanded(
                    child: _buildStatItem(
                      stats == null ? null : '${stats.credit.balance}p',
                      'Credit',
                      Icons.stars_rounded,
                      loading: loading,
                    ),
                  ),
                  _buildDivider(),
                  // 동작하지 않던 '북마크' 자리를 뱃지로 교체했다.
                  Expanded(child: _buildBadgeItem(stats?.credit.badge, loading: loading)),
                ],
              ),
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              _buildStatsErrorBanner(snapshot.error),
            ],
          ],
        );
      },
    );
  }

  /// [count]가 null이면 값을 모르는 상태다 — [loading]이면 스켈레톤, 아니면 '-'.
  /// **null을 0으로 대체하지 않는다.**
  Widget _buildStatItem(String? count, String label, IconData icon, {required bool loading}) {
    final Widget value = count != null
        ? Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
        : loading
            ? Container(
                width: 24,
                height: 18,
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
              )
            : Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[400]));

    return Column(children: [
      Icon(icon, color: LiveSpotTheme.primaryColor, size: 22),
      const SizedBox(height: 6),
      value,
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ]);
  }

  /// 뱃지는 서버가 준 emoji·label을 그대로 그린다(P27). 등급 컷을 앱에서 판정하지 않는다.
  Widget _buildBadgeItem(CreditBadge? badge, {required bool loading}) {
    final Widget content = badge != null
        ? CreditBadgeChip(badge: badge)
        : loading
            ? Container(
                width: 60,
                height: 22,
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
              )
            : Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[400]));

    return Column(children: [
      const SizedBox(height: 22), // 다른 칸의 아이콘 높이와 맞춘다
      const SizedBox(height: 6),
      content,
      const SizedBox(height: 2),
      Text('뱃지', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ]);
  }

  /// 조회 실패를 조용히 '-'로만 두면 "왜 안 나오지"의 원인을 알 수 없다.
  /// 서버가 준 원문 메시지를 그대로 노출한다.
  Widget _buildStatsErrorBanner(Object? error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '내 활동/크레딧을 불러오지 못했어요: ${error.toString().replaceFirst('Exception: ', '')}',
              style: TextStyle(fontSize: 11, color: Colors.red[400]),
            ),
          ),
          GestureDetector(
            onTap: _reloadStats,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('다시 시도',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red[600])),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Container(width: 1, height: 40, color: Colors.grey[200]);

  Widget _buildMenuSection() {
    final menuItems = [
      {'icon': Icons.edit_note, 'title': '내 제보', 'subtitle': '작성한 현장 제보 관리', 'onTap': _openMyReports},
      {'icon': Icons.question_answer_outlined, 'title': '내 Q&A', 'subtitle': '질문 및 답변 이력', 'onTap': _openMyQna},
      {'icon': Icons.stars_rounded, 'title': 'Credit 내역', 'subtitle': '포인트 획득/사용 이력', 'onTap': _openCreditLedger},
      {'icon': Icons.bookmark_outline, 'title': '북마크', 'subtitle': '저장한 관광지', 'onTap': _openBookmarks},
      {'icon': Icons.gps_fixed, 'title': 'GPS 인증 설정', 'subtitle': '위치 인증 및 알림 설정'},
      {'icon': Icons.notifications_outlined, 'title': '알림 설정', 'subtitle': 'Push 알림 관리'},
      {'icon': Icons.help_outline, 'title': '고객센터', 'subtitle': '문의 및 도움말'},
      {'icon': Icons.info_outline, 'title': '앱 정보', 'subtitle': 'LiveSpot v1.0.0'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: menuItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final onTap = item['onTap'] as VoidCallback?;
          return Column(children: [
            ListTile(
              leading: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: LiveSpotTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(item['icon'] as IconData, color: LiveSpotTheme.primaryColor, size: 20),
              ),
              title: Text(item['title'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(item['subtitle'] as String, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              trailing: Icon(Icons.chevron_right, color: Colors.grey[300]),
              // 아직 연결되지 않은 메뉴는 onTap이 없다 — 눌러도 아무 일이 없는 대신
              // 리플조차 없어서 "죽은 메뉴"임이 드러난다.
              onTap: onTap,
            ),
            if (index < menuItems.length - 1) Divider(height: 1, indent: 70, color: Colors.grey[100]),
          ]);
        }).toList(),
      ),
    );
  }

  Future<void> _openMyReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyReportsScreen()),
    );
  }

  Future<void> _openMyQna() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyQnaScreen()),
    );
  }

  // 북마크 개수는 마이페이지에 표시하지 않으므로(정책 P-B10a) 복귀 시 스탯을 다시
  // 부를 이유가 없다. BookmarksScreen은 진입할 때마다 스스로 목록을 새로 받는다.
  Future<void> _openBookmarks() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookmarksScreen()),
    );
  }

  Future<void> _openCreditLedger() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreditLedgerScreen()),
    );
    // 내역 화면에서 당겨서 새로고침했을 수 있으므로 돌아오면 스탯도 맞춘다.
    if (mounted) _reloadStats();
  }
}
