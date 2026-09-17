import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'gps_verified_badge.dart';

/// 질문·답변·현장 제보 카드가 공유하는 작성자 헤더 행: 아바타 — 닉네임 —
/// (현장인증 뱃지, 선택) — 시간. 세 카드의 형식을 하나로 통일하기 위해 뽑았다
/// (2026-09-17, 사용자 레퍼런스: 커뮤니티 앱의 "실시간 인기 글" 카드).
///
/// 아바타는 `profile_screen.dart::_defaultAvatar`와 같은 정책이다 — 닉네임 이니셜(P41)은
/// 폐기됐고, 모든 사용자가 공유하는 획일적인 기본 이미지(`assets/images/default_profile.png`)
/// 하나만 쓴다. 이 카드들은 질문자·답변자·제보자가 매번 다른 사람이라 카카오 프로필
/// 사진 URL이 없으므로(동의해도 여기까지 안 내려온다) 애초에 폴백 1단계뿐이다.
///
/// [gpsVerified]는 답변자·제보자에게만 준다 — 질문 등록은 위치 제한이 없어(function.md
/// 기능 3①) 질문자에게는 애초에 인증 개념이 없다. 기본값 false로 뒀으니 질문 카드는
/// 이 파라미터를 생략하면 된다.
///
/// [timeLabel]은 이미 포맷된 문자열을 받는다 — 카드마다 쓰는 시간 표기가 다르기
/// 때문이다(Q&A는 `Formatters.timeAgo`, 현장 제보는 `Formatters.reportRecency`).
/// 이 위젯이 포맷 방식을 고르면 그 차이가 사라진다.
class AuthorHeader extends StatelessWidget {
  final String nickname;
  final bool gpsVerified;
  final String timeLabel;

  const AuthorHeader({
    super.key,
    required this.nickname,
    this.gpsVerified = false,
    required this.timeLabel,
  });

  static const String _defaultProfileAsset = 'assets/images/default_profile.png';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 12,
          backgroundImage: AssetImage(_defaultProfileAsset),
        ),
        const SizedBox(width: 6),
        Text(nickname, style: LiveSpotTheme.caption.copyWith(fontWeight: FontWeight.w600)),
        if (gpsVerified) ...[
          const SizedBox(width: 4),
          const GpsVerifiedBadge(),
        ],
        const Spacer(),
        Text(timeLabel, style: LiveSpotTheme.label.copyWith(color: LiveSpotTheme.textSecondary)),
      ],
    );
  }
}
