import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/activity_counts.dart';
import '../../models/auth_user.dart';
import '../../models/credit_summary.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/credit_badge.dart';
import '../../widgets/login_required_sheet.dart';
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
  final AuthService _auth = AuthService();

  List<Map<String, dynamic>> _testUsers = [];
  String? _selectedTestUserId;
  bool _loadingTestUsers = false;

  // build 안에서 만들면 리빌드마다 재호출된다. initState에서 한 번만 만들고,
  // 사용자가 바뀌거나(로그인·로그아웃·테스트유저 전환) 내역 화면에서 돌아왔을 때만
  // 다시 만든다.
  //
  // **null이면 "아직 부를 수 없다"**는 뜻이다(비로그인). /credits/me·/reports/me는
  // 비로그인에 401이므로(계약 2절), 호출해 놓고 에러 배너를 띄우면 정상 상태를 오류로
  // 보고하는 셈이 된다 — 로그인 안내를 그린다.
  Future<_MyStats>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _statsFuture = _makeStatsFuture();
    if (kDebugMode) _loadTestUsers();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 로그인·로그아웃·테스트유저 전환으로 사용자가 바뀌면 크레딧·활동 통계를 다시 읽는다(P17).
  /// 알림 계층 재설정(P16)은 `app.dart`가 같은 [AuthService] 알림을 받아 처리한다.
  void _onAuthChanged() {
    if (!mounted) return;
    // 로그아웃은 테스트유저 해제까지 함께 일으키므로(AuthService.logout, F2-b)
    // 드롭다운 선택도 실제 값을 따라간다 — 안 맞추면 해제된 뒤에도 이름이 남는다.
    _selectedTestUserId = ApiService.testUserId;
    _reloadStats(); // setState는 여기서 한 번 돈다
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 마이 탭이 지금 막 보이게 됨 — 숨어 있는 동안 제보·답변으로 크레딧이 올랐을 수
    // 있다. 제보/답변 응답이 알려주는 건 그 한 건의 적립액(`credit_earned`)뿐이고
    // 누적 잔액·뱃지는 여기에 없으므로, 이 화면은 다시 묻는 수밖에 없다.
    if (widget.isActive && !oldWidget.isActive) {
      // 이미 이 프레임에서 리빌드가 진행 중이라 setState는 불필요하다.
      _statsFuture = _makeStatsFuture();
    }
  }

  /// 비로그인이면 null을 돌려준다 — 호출 자체를 하지 않는다.
  Future<_MyStats>? _makeStatsFuture() {
    if (!_auth.hasServerIdentity) return null;
    return _loadStats();
  }

  Future<_MyStats> _loadStats() async {
    final results = await Future.wait([
      ApiService().fetchMyCredit(),
      ApiService().fetchMyActivity(),
    ]);
    return _MyStats(results[0] as CreditSummary, results[1] as ActivityCounts);
  }

  void _reloadStats() {
    // 화살표 본문(`=> _statsFuture = _makeStatsFuture()`)으로 쓰면 대입식의 값인 Future가
    // setState의 반환값이 되어 "setState() callback argument returned a Future"로 터진다
    // (013에서 실제로 터진 버그). 블록 본문이라 반환값이 없다 — Future를 만드는 것 자체는
    // 여기서 해도 된다(await하지 않으므로 setState 안에서 비동기 작업을 기다리는 게 아니다).
    setState(() {
      _statsFuture = _makeStatsFuture();
    });
  }

  Future<void> _loadTestUsers() async {
    setState(() => _loadingTestUsers = true);
    try {
      final users = await ApiService().fetchTestUsers();
      if (mounted) {
        setState(() {
          _testUsers = users;
          // 저장값 복원은 **여기서 하지 않는다.** `main()`이 runApp 전에 이미 끝냈고
          // (거기에만 `kDebugMode` 가드가 있다), 복원 경로가 둘이면 한쪽에만 가드가
          // 붙는 F2의 비대칭이 그대로 되살아난다. 여기서는 런타임 값을 읽기만 한다.
          _selectedTestUserId = ApiService.testUserId;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingTestUsers = false);
    }
  }

  /// [userId]가 `null`이면 **해제**다(드롭다운 첫 항목). 예전에는 여기서 바로 return해
  /// 해제할 방법이 아예 없었고, 그래서 한 번이라도 테스트유저를 고른 브라우저에서는
  /// 비로그인 UX를 두 번 다시 관찰할 수 없었다(QA 1회차 F2-a — 수용 기준 검증 자체가 막혔다).
  Future<void> _onSelectTestUser(String? userId) async {
    setState(() => _selectedTestUserId = userId);
    // ApiService.testUserId에 직접 대입하거나 prefs를 직접 쓰지 않는다 — AuthService를
    // 거쳐야 저장·삭제가 한 곳에 남고, 알림 계층 재설정(P16)과 통계 재조회(P17)가
    // app.dart·_onAuthChanged에서 자동으로 일어난다. 이 드롭다운이 기능 6·8 다인원
    // 시연의 유일한 진입점이라(013 일지 253행) 그 연결이 빠지면 조용히 이전 사용자의
    // 배지가 남는다.
    await _auth.setTestUserId(userId);
    if (!mounted) return;
    final message = userId == null
        ? '테스트 유저 해제 — 비로그인 상태입니다'
        : '테스트 유저 전환: ${_testUserLabel(_testUsers.firstWhere(
            (u) => u['id'] == userId,
            orElse: () => <String, dynamic>{'id': userId},
          ))}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Pretendard'))),
    );
  }

  /// `/dev/test-users` 한 행 → 화면에 띄울 이름. **캐스팅 지점은 여기 한 곳뿐이다.**
  ///
  /// 닉네임 미설정은 이제 **정상 상태**다(P25: `nickname IS NULL` 하나가 곧 미설정이다).
  /// 그래서 `dev.py:49`는 `{"id": "...", "nickname": null}`을 정직하게 내려주는데,
  /// 드롭다운(`build` 안)과 스낵바가 각자 그 값을 다뤘고 각자 틀렸다 — 드롭다운은
  /// `as String`으로 캐스팅해 **프로필 화면 전체가 build 중 TypeError로 죽었고**
  /// (`fetchTestUsers`의 `catch`는 `DioException`만 잡아 막지 못한다), 스낵바는
  /// `dynamic` 보간이라 컴파일러에 걸리지 않은 채 `"null"`을 그대로 찍었다(QA 1회차 F1).
  /// 두 호출부가 이 함수를 공유하는 한 다음 화면이 늘어도 같은 실수가 반복되지 않는다.
  ///
  /// 폴백은 서버 `nickname.py`의 `UNKNOWN_NICKNAME`("알 수 없음")과 같은 성격이되
  /// 문구는 이 화면의 것을 쓴다 — 여기서 null은 사고 신호가 아니라 "아직 안 정했다"이고,
  /// **닉네임 미설정 사용자로 전환해 403 NICKNAME_REQUIRED와 강제 모달을 재현하는 것이
  /// 이 드롭다운의 QA 용도 그 자체**라(02 계약 R4·03 배선 R2의 재현 절차) 그 행을
  /// 감추거나 걸러내면 안 된다. id를 함께 보여줘야 미설정 행이 여럿일 때 구분된다.
  String _testUserLabel(Map<String, dynamic> user) {
    final nickname = user['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;
    final id = user['id'] as String?;
    return id == null ? '(닉네임 미설정)' : '$id (닉네임 미설정)';
  }

  // ---------------------------------------------------------------------------
  // 로그인 / 로그아웃 (기능 9)
  // ---------------------------------------------------------------------------

  Future<void> _openLoginSheet() async {
    // 시트 하나로 로그인 UI를 통일한다 — 카카오 버튼·에러 문구·취소 처리의 사본을
    // 여기에 또 만들면 둘이 서서히 달라진다.
    await promptLogin(context, actionLabel: '마이페이지');
    // 성공하면 AuthService가 리스너를 깨워 _onAuthChanged가 통계를 다시 읽는다.
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('로그아웃', style: TextStyle(fontFamily: 'Pretendard', fontSize: 17)),
        content: const Text(
          '로그아웃하면 제보·질문·답변과 북마크를 이용할 수 없어요.\n같은 카카오 계정으로 다시 로그인하면 활동 이력과 크레딧은 그대로 남아 있습니다.',
          style: TextStyle(fontFamily: 'Pretendard', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소', style: TextStyle(fontFamily: 'Pretendard')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('로그아웃', style: TextStyle(fontFamily: 'Pretendard', color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 로그아웃은 **서버 호출이 없다**(백엔드 계약 3절). 클라이언트가 토큰을 지우는 것이
    // 전부다 — 저장소에서 삭제 + ApiService.accessToken = null 까지가 AuthService.logout().
    await _auth.logout();

    // 알림 정리(P16). app.dart가 AuthService 알림을 받아 같은 처리를 중앙에서 하지만,
    // 014의 실제 버그가 "사용자 전환 경로에서 이 호출이 빠진 것"이었으므로 로그아웃
    // 경로에도 명시적으로 남긴다. 멱등이다 — stop() 이후에는 상태만 비우고 끝난다.
    NotificationService().resetForUserSwitch();

    if (!mounted) return;
    // 크레딧·활동 통계 재조회(P17). 비로그인이 됐으므로 실제로는 호출하지 않고
    // 로그인 안내로 바뀐다(_makeStatsFuture가 null을 준다).
    _reloadStats();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그아웃되었습니다', style: TextStyle(fontFamily: 'Pretendard'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 로그인 상태가 바뀌면 프로필 카드·메뉴가 함께 다시 그려져야 한다.
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) => Scaffold(
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
          else ...[
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedTestUserId,
              hint: const Text('선택 안 함 (비로그인)'),
              items: [
                // **해제 항목.** 이게 없으면 한 번 고른 테스트유저를 되돌릴 길이 없어
                // 그 브라우저에서는 비로그인 UX(로그인 유도 시트·AC2·AC7)를 다시
                // 관찰할 수 없다(QA 1회차 F2-a).
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('선택 안 함 (비로그인)'),
                ),
                ..._testUsers.map((u) => DropdownMenuItem<String>(
                      value: u['id'] as String,
                      child: Text(_testUserLabel(u), overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: _auth.isLoggedIn ? null : _onSelectTestUser,
            ),
            if (_auth.isLoggedIn)
              Text(
                '실제 로그인 중에는 테스트유저 헤더가 서버에서 무시됩니다(계약 2절). 전환하려면 먼저 로그아웃하세요.',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.4),
              )
            else ...[
              const SizedBox(height: 4),
              // 카카오 키가 아직 없어도 로그인 이후 화면(프로필 카드·로그아웃·게이트 해제·
              // WS ?token=)을 검증할 수 있게 해주는 경로다(계약 7절 9번).
              // 서버 TEST_MODE가 꺼져 있으면 404라 운영에서는 동작하지 않는다.
              TextButton.icon(
                onPressed: _selectedTestUserId == null ? null : _devLoginAsSelected,
                icon: const Icon(Icons.vpn_key_outlined, size: 16),
                label: const Text('선택한 유저로 실제 로그인(JWT 발급)', style: TextStyle(fontSize: 12, fontFamily: 'Pretendard')),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _devLoginAsSelected() async {
    final userId = _selectedTestUserId;
    if (userId == null) return;
    try {
      final result = await _auth.loginAsDevUser(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        // 닉네임은 이제 nullable이다(P25). `?? `가 없으면 스낵바에 "null"이 그대로 찍힌다
        // — 문자열 보간은 타입 검사를 빠져나간다.
        SnackBar(
          content: Text(
            '개발용 로그인: ${result.user.nickname ?? '(닉네임 미설정)'}',
            style: const TextStyle(fontFamily: 'Pretendard'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('개발용 로그인 실패: ${e.toString().replaceFirst('Exception: ', '')}', style: const TextStyle(fontFamily: 'Pretendard'))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 프로필 카드 — 로그인 전/중/후 세 가지 모습
  // ---------------------------------------------------------------------------

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF1565C0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1E88E5).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: _auth.isLoggedIn ? _buildLoggedInCard(_auth.user!) : _buildLoggedOutCard(),
    );
  }

  Widget _buildLoggedInCard(AuthUser user) {
    return Row(
      children: [
        _buildAvatar(user.profileImageUrl, nickname: user.nickname),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 닉네임은 이제 사용자가 직접 정한 **unique** 값이지만(P24), 그래도 표시
              // 계층의 값일 뿐이다 — 사용자 구분·매칭에는 user.userId(UUID)만 쓴다.
              //
              // null은 "아직 정하지 않음"이다(P25). 강제 모달(P42) 때문에 실제로는 이
              // 화면에 닿기 전에 처리되지만, 카드가 "null"을 그리는 일은 없어야 한다.
              Text(
                user.nickname ?? '닉네임 설정이 필요해요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('카카오 계정으로 로그인됨', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  /// 아바타. 폴백은 **이미지 → 닉네임 이니셜 → 사람 아이콘** 순서다(P41).
  ///
  /// [imageUrl]은 이제 **항상 null이다** — 카카오 프로필 사진 동의를 받지 않기로 했다
  /// (P34·P39). 그래도 이미지 분기를 **지우지 않는다**(P40): 앱 자체 프로필 이미지
  /// 업로드가 붙을 때 이 자리가 그대로 쓰인다(`images.py` 라우터가 이미 있다).
  ///
  /// 이니셜을 넣은 이유는, 아무것도 안 하면 로그인 사용자 **전원이 똑같은 회색 사람
  /// 아이콘**이 되어 오늘 카카오 사진이 뜨던 자리가 눈에 띄게 비어 보이기 때문이다.
  /// 닉네임이 unique해졌으므로(P24) 첫 글자는 실제 구분 정보를 담는다.
  Widget _buildAvatar(String? imageUrl, {String? nickname}) {
    final fallback = _buildAvatarFallback(nickname);
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.2),
        border: Border.all(color: Colors.white38, width: 2),
      ),
      child: imageUrl == null
          ? fallback
          : ClipOval(
              child: Image.network(
                imageUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
            ),
    );
  }

  /// 닉네임 첫 **코드포인트**를 원 안에 그린다. 닉네임이 없으면(미설정·비로그인)
  /// 기존 사람 아이콘 그대로다.
  ///
  /// `nickname[0]`이 아니라 `runes.first`인 이유: 허용 문자가 한글·영문·숫자·밑줄뿐이라
  /// 지금은 결과가 같지만, 규칙이 풀렸을 때 `[0]`은 서로게이트 페어를 반쪽만 잘라
  /// 깨진 글자를 그린다.
  Widget _buildAvatarFallback(String? nickname) {
    const personIcon = Center(child: Icon(Icons.person, color: Colors.white, size: 30));
    if (nickname == null || nickname.isEmpty) return personIcon;

    return Center(
      child: Text(
        String.fromCharCode(nickname.runes.first),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLoggedOutCard() {
    // 복원 중(P19)에는 "로그인하세요"를 띄우지 않는다 — 복원에 성공할 사용자에게
    // 로그인 권유가 한 번 번쩍이는 것을 막는다.
    if (_auth.isRestoring) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            _buildAvatar(null),
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
        // 토큰은 있는데 서버에 물어보지 못한 경우(P20의 401이 아닌 실패). 조용히 비로그인
        // 취급하면 멀쩡한 세션이 사라진 것처럼 보이므로 다시 시도할 기회를 준다.
        if (_auth.restoreError != null) ...[
          const SizedBox(height: 12),
          _buildRestoreErrorBanner(_auth.restoreError!),
        ],
        const SizedBox(height: 16),
        // 로그인 수단은 카카오 하나만이다(P1 / function.md:83).
        Row(children: [
          Expanded(child: _buildLoginButton('카카오 로그인', const Color(0xFFFEE500), Colors.black87, _openLoginSheet)),
        ]),
      ],
    );
  }

  Widget _buildRestoreErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // 파란 그라데이션 카드 위에 얹는 반투명 흰색(15%). withOpacity는 deprecated라
        // 새 코드에서는 알파를 직접 쓴다.
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '로그인 상태를 확인하지 못했어요: $message',
              style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'Pretendard'),
            ),
          ),
          GestureDetector(
            onTap: () => _auth.restore(),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('다시 시도',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Pretendard')),
            ),
          ),
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
  //
  // **비로그인은 실패가 아니다.** 호출 자체를 하지 않고(401이 뻔하므로) '-' + 회색 안내를
  // 그린다 — 에러 배너를 띄우면 정상 상태를 오류로 보고하는 셈이 된다.
  // ---------------------------------------------------------------------------

  Widget _buildStatsSection() {
    final future = _statsFuture;
    if (future == null) return _buildStatsShell(null, loading: false, footer: _buildLoginPrompt());

    return FutureBuilder<_MyStats>(
      future: future,
      builder: (context, snapshot) {
        final bool loading = snapshot.connectionState == ConnectionState.waiting;
        final bool failed = snapshot.hasError;
        final _MyStats? stats = failed ? null : snapshot.data;

        return _buildStatsShell(
          stats,
          loading: loading,
          footer: failed ? _buildStatsErrorBanner(snapshot.error) : null,
        );
      },
    );
  }

  Widget _buildStatsShell(_MyStats? stats, {required bool loading, Widget? footer}) {
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
        if (footer != null) ...[
          const SizedBox(height: 8),
          footer,
        ],
      ],
    );
  }

  Widget _buildLoginPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '로그인하면 내 제보·답변·Credit을 볼 수 있어요.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600], fontFamily: 'Pretendard'),
            ),
          ),
        ],
      ),
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
    final menuItems = <Map<String, dynamic>>[
      {'icon': Icons.edit_note, 'title': '내 제보', 'subtitle': '작성한 현장 제보 관리', 'onTap': _openMyReports},
      // 2026-09-12 사용자 지침: 알림 화면(질문/답변 알림 + Push 설정)을 내 Q&A로
      // 통합했다 — 어차피 질문/답변 목록을 보여주는 화면이라 하나로 합친다.
      // 'badge' 항목은 미읽음 수를 오른쪽에 그리라는 표시다.
      // 2026-09-13 사용자 지침: 부제를 "질문·답변 이력"만 남긴다 — 015에서 "알림"
      // 탭이 사라진 뒤로 "및 알림"이라는 문구가 실제 화면 구성과 어긋나 있었다.
      {
        'icon': Icons.question_answer_outlined,
        'title': '내 Q&A',
        'subtitle': '내 질문·답변 이력',
        'onTap': _openMyQna,
        'badge': true,
      },
      {'icon': Icons.stars_rounded, 'title': 'Credit 내역', 'subtitle': '포인트 획득/사용 이력', 'onTap': _openCreditLedger},
      {'icon': Icons.bookmark_outline, 'title': '북마크', 'subtitle': '저장한 관광지', 'onTap': _openBookmarks},
      {'icon': Icons.help_outline, 'title': '고객센터', 'subtitle': '문의 및 도움말'},
      {'icon': Icons.info_outline, 'title': '앱 정보', 'subtitle': 'LiveSpot v1.0.0'},
      // 로그아웃은 **신규 항목**이다(01_spec 쟁점 D). function.md:24가 "계정(로그아웃)은
      // 죽은 메뉴"라고 쓴 것과 달리 메뉴 자체가 없었다 — 014에서 죽은 메뉴들을 정리할 때
      // 함께 사라졌다. 비로그인 상태에서는 아예 그리지 않는다(누를 대상이 없다).
      if (_auth.isLoggedIn)
        {
          'icon': Icons.logout,
          'title': '로그아웃',
          // ⚠️ 이 Map은 값 타입이 `dynamic`이라 **컴파일러가 null을 잡아 주지 않는다.**
          // 닉네임이 nullable이 된 뒤(P25) 여기에 null이 들어가면, 아래 701행쯤의
          // `item['subtitle'] as String`이 런타임에 터지거나 부제가 "null"로 뜬다.
          // 01_spec 7절이 "조용한 파급 4곳" 중 첫 번째로 지목한 자리다.
          'subtitle': _auth.user!.nickname ?? '닉네임 미설정',
          'onTap': _logout,
          'danger': true,
        },
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
          final danger = item['danger'] == true;
          final color = danger ? Colors.red.shade400 : LiveSpotTheme.primaryColor;
          return Column(children: [
            ListTile(
              leading: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(item['icon'] as IconData, color: color, size: 20),
              ),
              title: Text(
                item['title'] as String,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: danger ? Colors.red.shade400 : null),
              ),
              subtitle: Text(item['subtitle'] as String, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              trailing: item['badge'] == true
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildUnreadBadge(),
                        Icon(Icons.chevron_right, color: Colors.grey[300]),
                      ],
                    )
                  : Icon(Icons.chevron_right, color: Colors.grey[300]),
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

  /// 미읽음 알림 배지. 전역 알림 서비스를 구독하므로 이 화면에 머무는 동안에도 실시간으로
  /// 숫자가 갱신된다(WebSocket, 끊기면 7초 폴백 폴링). 0건이면 아무것도 그리지 않는다 —
  /// "0"을 띄우면 알림이 온 것처럼 보인다.
  Widget _buildUnreadBadge() {
    return ListenableBuilder(
      listenable: NotificationService(),
      builder: (context, _) {
        final count = NotificationService().unreadCount;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFFFF1744), borderRadius: BorderRadius.circular(10)),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  // ── MyPage 하위 화면 (전부 로그인 필요, 계약 2절) ──
  //
  // 버튼을 숨기지 않고 눌리게 두되 로그인 시트로 유도한다(Q5-C). 게이트는
  // ensureLoggedIn 하나만 쓴다 — 화면마다 조건문을 따로 쓰면 새 메뉴에서 빠진다.

  Future<void> _openMyReports() async {
    if (!await ensureLoggedIn(context, actionLabel: '내 제보 보기')) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyReportsScreen()),
    );
  }

  Future<void> _openMyQna() async {
    if (!await ensureLoggedIn(context, actionLabel: '내 Q&A 보기')) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyQnaScreen()),
    );
  }

  // 북마크 개수는 마이페이지에 표시하지 않으므로(정책 P-B10a) 복귀 시 스탯을 다시
  // 부를 이유가 없다. BookmarksScreen은 진입할 때마다 스스로 목록을 새로 받는다.
  Future<void> _openBookmarks() async {
    if (!await ensureLoggedIn(context, actionLabel: '북마크')) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookmarksScreen()),
    );
  }

  Future<void> _openCreditLedger() async {
    if (!await ensureLoggedIn(context, actionLabel: 'Credit 내역 보기')) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreditLedgerScreen()),
    );
    // 내역 화면에서 당겨서 새로고침했을 수 있으므로 돌아오면 스탯도 맞춘다.
    if (mounted) _reloadStats();
  }
}
