import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/nickname_rules.dart';

/// 닉네임을 정할 때까지 앱 전체를 덮는 **강제 모달**(Q1-A 확정).
///
/// ─────────────────────────────────────────────────────────────────────────────
/// **이것은 라우트도 바텀시트도 아니다.** `app.dart`의 `MaterialApp.builder` Stack에
/// Navigator보다 **위에** 겹쳐 그리는 전면 레이어다. 이렇게 만든 이유:
///
///   1. **닫을 방법이 구조적으로 없다.** 라우트로 만들면 브라우저 뒤로가기·`Navigator.pop`·
///      바깥 탭 등 닫히는 경로가 여럿 생기고, 그걸 전부 `if`로 막아야 한다. 명세의
///      "닫기 불가"를 조건문이 아니라 **구조로** 강제한다.
///   2. **띄우는 지점이 한 곳이다**(P42). `showDialog`를 쓰면 "언제 띄우고 언제 닫는가"를
///      화면마다 관리하게 되고, 그게 016의 F1·F2·F3(판정이 흩어져 난 버그 3건)와 같은
///      계열이다. 여기서는 `AuthService.needsNickname`이 true인 동안 **존재할 뿐**이라
///      띄우고 닫는 코드 자체가 없다.
///
/// 파일 이름이 명세의 `nickname_setup_sheet.dart`와 다른 것은 의도적이다 — 시트가
/// 아닌데 시트라고 부르면 다음 사람이 `showModalBottomSheet` 호출부를 찾게 된다.
/// ─────────────────────────────────────────────────────────────────────────────
///
/// **로그아웃 버튼은 이 화면의 필수 구성이다.** 서버 장애로 제출이 계속 실패해도
/// 사용자가 빠져나갈 수 있어야 한다 — 닫기가 불가능한 화면에 탈출구가 없으면 앱이
/// 통째로 잠긴다(01_spec 4절 Q1-A의 경고).
class NicknameSetupGate extends StatefulWidget {
  const NicknameSetupGate({super.key});

  @override
  State<NicknameSetupGate> createState() => _NicknameSetupGateState();
}

/// 입력창 아래 안내 문구의 성격. 색만 다른 게 아니라 **뜻이 다르다** —
/// [neutral]은 "확인하지 못했다"이지 "쓸 수 없다"가 아니라서, 제출을 막지 않는다.
enum _HintTone { ok, error, neutral }

class _NicknameSetupGateState extends State<NicknameSetupGate> {
  final TextEditingController _controller = TextEditingController();

  /// `spot_search_delegate.dart:93`의 400ms 디바운스 패턴을 그대로 복제했다 —
  /// 이 프로젝트의 디바운스 선례가 그것 하나뿐이라 방식을 늘리지 않는다.
  Timer? _debounce;

  bool _checking = false;
  String? _hint;
  _HintTone _hintTone = _HintTone.neutral;

  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 클라이언트 검증은 **편의일 뿐이다.** 최종 판정은 서버의 400/409이고, 여기서 막는
  /// 것은 "뻔히 틀린 입력으로 왕복하지 않게" 하는 정도다. 규칙을 서버보다 조이면
  /// 서버가 허용하는 닉네임을 앱이 거부하게 되므로 **더 조이지 않는다.**
  ///
  /// 규칙 자체는 `utils/nickname_rules.dart`에 있다 — 이 위젯 안에 정규식과 길이 제한을
  /// 두었더니 서버의 NFC 정규화 단계(P30 ②)만 빠진 채 복제됐고, NFD로 입력된 멀쩡한
  /// 한글을 **서버보다 먼저 거부**했다(QA 1회차 F2). 닫을 수 없는 모달에서의 부당한
  /// 거부는 앱이 잠기는 것과 같다.
  String? _localValidate(String value) => validateNickname(value);

  void _onChanged(String raw) {
    final value = raw.trim();
    _debounce?.cancel();

    setState(() {
      _submitError = null;
      _hint = null;
      _hintTone = _HintTone.neutral;
      _checking = false;
    });

    if (value.isEmpty) return;

    final localError = _localValidate(value);
    if (localError != null) {
      // 형식이 틀렸으면 서버에 묻지 않는다. 서버도 200 + reason으로 같은 답을 주지만,
      // 매 키 입력마다 왕복할 이유가 없다.
      setState(() {
        _hint = localError;
        _hintTone = _HintTone.error;
      });
      return;
    }

    setState(() => _checking = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _check(value));
  }

  Future<void> _check(String value) async {
    try {
      final result = await ApiService().checkNicknameAvailable(value);
      // 응답이 늦게 도착하는 사이 사용자가 더 입력했을 수 있다. 지금 입력창에 있는
      // 값에 대한 답이 아니면 버린다 — 아니면 "두 글자 전"의 판정이 화면에 남는다.
      if (!mounted || _controller.text.trim() != value) return;
      setState(() {
        _checking = false;
        _hint = result.available ? '사용할 수 있는 닉네임이에요' : (result.reason ?? '사용할 수 없는 닉네임이에요');
        _hintTone = result.available ? _HintTone.ok : _HintTone.error;
      });
    } catch (_) {
      if (!mounted || _controller.text.trim() != value) return;
      // 중복 확인 실패는 "쓸 수 없다"가 아니다. 빨간 문구로 보여주면 멀쩡한 닉네임을
      // 사용자가 스스로 포기한다 — 회색으로 알리고 제출은 그대로 열어 둔다.
      setState(() {
        _checking = false;
        _hint = '지금은 중복 확인을 할 수 없어요. 그대로 제출해 볼 수 있어요.';
        _hintTone = _HintTone.neutral;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final value = _controller.text.trim();

    final localError = _localValidate(value);
    if (localError != null) {
      setState(() => _submitError = localError);
      return;
    }

    _debounce?.cancel();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await AuthService().submitNickname(value);
      // 성공하면 `needsNickname`이 false가 되고 `app.dart`가 이 위젯을 트리에서
      // 걷어낸다. 여기서 무언가를 닫거나 setState할 필요가 없다 — 있으면 그게 곧
      // 두 번째 판정 지점이다.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // 서버 문구를 그대로 띄운다. 409("이미 사용 중인 닉네임이에요")는 실시간
        // 확인이 초록불이었어도 날 수 있다 — 확인과 제출 사이의 선점은 서버만 막는다.
        _submitError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _logout() async {
    _debounce?.cancel();
    await AuthService().logout();
    // 로그아웃하면 user가 null이 되어 needsNickname도 false다 → 이 레이어가 사라진다.
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: LiveSpotTheme.backgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 28),
                  _buildField(),
                  const SizedBox(height: 8),
                  _buildHintRow(),
                  if (_submitError != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(_submitError!),
                  ],
                  const SizedBox(height: 20),
                  _buildSubmitButton(),
                  const SizedBox(height: 4),
                  _buildLogoutButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE3F2FD),
          ),
          child: const Icon(Icons.badge_outlined, size: 30, color: LiveSpotTheme.primaryColor),
        ),
        const SizedBox(height: 16),
        const Text(
          '닉네임을 정해 주세요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: LiveSpotTheme.textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'LiveSpot에서 쓸 이름이에요.\n제보와 질문·답변에 이 이름으로 표시됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            height: 1.5,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildField() {
    return TextField(
      controller: _controller,
      autofocus: true,
      enabled: !_submitting,
      maxLength: 12,
      textInputAction: TextInputAction.done,
      onChanged: _onChanged,
      onSubmitted: (_) => _submit(),
      // 공백은 애초에 들어가지 않게 막는다. 서버도 거부하지만("한글, 영문, 숫자,
      // 밑줄(_)만"), 스페이스를 눌렀는데 아무 일도 일어나지 않는 편이 입력 도중
      // 빨간 문구가 번쩍이는 것보다 낫다.
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      style: const TextStyle(fontFamily: 'Pretendard', fontSize: 16),
      decoration: InputDecoration(
        hintText: '예: 여행하는밤톨_1',
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LiveSpotTheme.primaryColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildHintRow() {
    if (_checking) {
      return Row(
        children: [
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(
            '사용할 수 있는지 확인 중…',
            style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      );
    }

    final hint = _hint;
    if (hint == null) {
      return Text(
        '2~12자, 한글·영문·숫자·밑줄(_)만 쓸 수 있어요.',
        style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: Colors.grey[500]),
      );
    }

    final (color, icon) = switch (_hintTone) {
      _HintTone.ok => (Colors.green[600]!, Icons.check_circle_outline),
      _HintTone.error => (Colors.red[400]!, Icons.error_outline),
      _HintTone.neutral => (Colors.grey[600]!, Icons.info_outline),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hint,
            style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: color, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
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
              message,
              style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: Colors.red[400], height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: LiveSpotTheme.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text(
                '이 닉네임으로 시작하기',
                style: TextStyle(fontFamily: 'Pretendard', fontSize: 15, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  /// 이 화면의 **유일한 탈출구**다. 지우지 말 것 — 서버가 닉네임 제출을 계속 거부하는
  /// 동안 이 버튼이 없으면 사용자는 앱에 갇힌다(01_spec 4절 Q1-A).
  Widget _buildLogoutButton() {
    return TextButton(
      onPressed: _submitting ? null : _logout,
      child: Text(
        '로그아웃',
        style: TextStyle(fontFamily: 'Pretendard', fontSize: 13, color: Colors.grey[500]),
      ),
    );
  }
}
