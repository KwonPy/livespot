import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../services/auth_service.dart';
import '../services/kakao_login_bridge.dart';

/// 비로그인 사용자가 쓰기 동작을 시도했을 때의 **유일한 게이트**(Q5-C).
///
/// ─────────────────────────────────────────────────────────────────────────────
/// 정책: 버튼을 **숨기지 않는다.** 숨기면 사용자가 기능의 존재 자체를 모른다
/// (`function.md:85` "보는 건 자유, 참여는 로그인"). 눌리게 두되 로그인 시트로 유도한다.
///
/// 이 파일이 게이트의 유일한 구현이다. 호출부는 [ensureLoggedIn] 한 줄만 쓰고, 각자
/// `if (!isLoggedIn) ...`를 쓰지 않는다 — 조건문으로 흩어 놓으면 새 호출부가 생길 때마다
/// 조용히 빠진다.
///
/// ⚠️ **이 게이트는 보안 경계가 아니다.** 401을 보장하는 것은 서버뿐이다(AC2).
/// 여기서 막는 것은 UX일 뿐이라, 서버 쪽 `Depends(get_current_user_id)`를 대체하지 않는다.
/// ─────────────────────────────────────────────────────────────────────────────
///
/// 반환값은 "이제 진행해도 되는가"다. 이미 로그인돼 있으면 시트를 띄우지 않고 바로 true.
Future<bool> ensureLoggedIn(
  BuildContext context, {
  /// "…하려면 로그인이 필요해요"의 앞부분. 예: `'제보'`, `'질문 작성'`, `'북마크'`.
  required String actionLabel,
}) async {
  // 개발 빌드의 테스트유저 헤더도 서버가 받아들이는 식별 경로다(계약 2절 ②).
  // isLoggedIn만 보면 013~015의 다인원 QA 시나리오가 전부 이 시트에 막힌다.
  if (AuthService().hasServerIdentity) return true;
  return promptLogin(context, actionLabel: actionLabel);
}

/// 조건 없이 로그인 시트를 띄운다. 프로필 화면의 카카오 버튼처럼 **로그인 자체가 목적인**
/// 자리에서 쓴다 — [ensureLoggedIn]을 쓰면 테스트유저 헤더가 설정된 개발 빌드에서
/// 버튼이 아무 반응도 하지 않는다.
Future<bool> promptLogin(BuildContext context, {String actionLabel = '이 기능'}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => LoginRequiredSheet(actionLabel: actionLabel),
  );
  return result == true;
}

/// [ensureLoggedIn]이 띄우는 시트. 직접 쓰지 말고 [ensureLoggedIn]을 쓸 것 —
/// 그래야 "이미 로그인돼 있으면 띄우지 않는다"는 판정이 한 곳에 남는다.
class LoginRequiredSheet extends StatefulWidget {
  final String actionLabel;

  const LoginRequiredSheet({super.key, required this.actionLabel});

  @override
  State<LoginRequiredSheet> createState() => _LoginRequiredSheetState();
}

class _LoginRequiredSheetState extends State<LoginRequiredSheet> {
  bool _loggingIn = false;
  String? _error;

  Future<void> _login() async {
    if (_loggingIn) return;
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      await AuthService().loginWithKakao();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on KakaoLoginException catch (e) {
      if (!mounted) return;
      // 팝업을 그냥 닫은 것까지 빨간 에러로 보여주면 사용자가 자기가 뭘 잘못했다고
      // 오해한다. 취소는 시트를 그대로 둔 채 아무 말도 하지 않는다.
      setState(() {
        _loggingIn = false;
        _error = e.isCancelled ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      // 서버가 준 문구를 그대로 보여준다. 특히 502(카카오 서버 장애)를 "다시
      // 로그인하세요"로 바꿔 쓰면 사용자가 몇 번을 눌러도 되지 않는다.
      setState(() {
        _loggingIn = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 20),
          Text(
            '로그인이 필요합니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[850],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.actionLabel}은(는) 로그인 후 이용할 수 있어요.\n'
            '둘러보기는 로그인 없이도 계속 하실 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Pretendard', fontSize: 13, color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Container(
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
                      _error!,
                      style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: Colors.red[400]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 키가 아직 없는 빌드에서도 버튼은 눌린다 — 누르면 크래시 대신 위 에러 칸에
          // "키가 설정되지 않았다"가 뜬다(계약 7절 8번). 미리 안내도 함께 보여준다.
          if (!AppConstants.hasKakaoJsKey) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Text(
                '이 빌드에는 카카오 JavaScript 키가 주입되지 않았어요.\n'
                '--dart-define=KAKAO_JS_KEY=... 로 다시 빌드해야 로그인할 수 있습니다.',
                style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: Colors.amber[900], height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildKakaoButton(),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loggingIn ? null : () => Navigator.of(context).pop(false),
            child: Text(
              '나중에 할게요',
              style: TextStyle(fontFamily: 'Pretendard', fontSize: 13, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKakaoButton() {
    return GestureDetector(
      onTap: _loggingIn ? null : _login,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE500), // 카카오 브랜드 컬러 — 프로필 카드 버튼과 동일
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _loggingIn
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                )
              : const Text(
                  '카카오로 시작하기',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
