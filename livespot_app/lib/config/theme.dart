import 'package:flutter/material.dart';

class LiveSpotTheme {
  static const Color primaryColor = Color(0xFF1E88E5); // Vibrant blue
  static const Color accentColor = Color(0xFFFF6D00); // Warm orange
  static const Color backgroundColor = Color(0xFFFAFBFC);
  static const Color textColor = Color(0xFF333333);

  /// 카드가 배경(#FAFBFC)과 거의 같은 흰색이라 경계가 안 보이는 문제 완화용 보더.
  /// 배경/카드 색은 그대로 두고, 옅은 보더 한 줄로만 표면을 구분한다.
  static const Color borderColor = Color(0xFFE2E8F0);

  /// 혼잡도 3단계(여유/보통/높음, EASY/NORMAL/BUSY 양쪽 다 공유)에서 쓰는 신호등 색.
  /// warningColor는 일부러 accentColor(#FF6D00)와 다른 톤(앰버)을 써서, CTA 주황과
  /// "보통" 경고 배지가 서로 헷갈리지 않게 한다.
  static const Color successColor = Color(0xFF43A047);
  static const Color warningColor = Color(0xFFFFA000);
  static const Color dangerColor = Color(0xFFE53935);

  /// 화면 좌우 기본 여백. explore/spot_detail/feed/profile은 이미 16을 쓰고 있었고,
  /// live_screen/credit_ledger만 20을 써서 탭 이동 시 콘텐츠 정렬선이 흔들렸다 — 16으로 통일.
  static const double screenPadding = 16;

  /// live_badge/crowdedness_badge/gps_verified_badge/credit_badge(기본 크기)처럼
  /// "작은 상태 pill" 계열이 공유하는 padding·radius.
  static const EdgeInsets badgePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  static const double badgeRadius = 8;

  /// 보조 텍스트 전용 회색. `Colors.grey[400]`(≈1.9:1)·`[500]`(≈2.7:1)·`[600]`(≈4.6:1,
  /// AA 4.5:1 경계에 걸침)은 흰 배경에서 본문 대비 기준을 못 넘기거나 위태롭게 걸친다.
  /// grey.shade700(≈6.2:1)로 통일해 여유 있게 넘긴다(design_brief.md §2 문제 1).
  /// `grey[700]`/`[800]`처럼 이미 충분히 어두운 값은 그대로 두어도 된다 — 이 토큰은
  /// 실패/경계 구간(400·500·600)을 대체하는 용도다. 장식용 보더·아이콘 회색은 대상 아님.
  static const Color textSecondary = Color(0xFF616161); // Colors.grey.shade700과 동일 값

  /// 타이포그래피 스케일 5단(design_brief.md §2 문제 2 / §1-1 결정: 5단, heading 포함).
  /// 화면마다 fontSize를 즉석으로 고르지 않고 아래 5개 중 하나를 쓴다. 색은 지정하지 않는다
  /// (문맥마다 textColor/textSecondary/흰색 등이 달라 호출부에서 copyWith(color: ...)로 얹는다).
  static const String _fontFamily = 'Pretendard';
  static const TextStyle heading = TextStyle(fontFamily: _fontFamily, fontSize: 20, fontWeight: FontWeight.bold);
  static const TextStyle title = TextStyle(fontFamily: _fontFamily, fontSize: 18, fontWeight: FontWeight.bold);
  static const TextStyle body = TextStyle(fontFamily: _fontFamily, fontSize: 14, fontWeight: FontWeight.normal);
  static const TextStyle caption = TextStyle(fontFamily: _fontFamily, fontSize: 12, fontWeight: FontWeight.normal);
  static const TextStyle label = TextStyle(fontFamily: _fontFamily, fontSize: 11, fontWeight: FontWeight.w500);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentColor,
        background: backgroundColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Pretendard',
        ),
      ),
      fontFamily: 'Pretendard',
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

/// 4px 배수 스페이싱 스케일. 전체 화면 일괄 치환 대신 화면 단위로 단계적으로
/// 적용한다 — 첫 적용 대상은 live_screen.dart(간격 값이 화면마다/한 화면 안에서도
/// 제각각이던 문제).
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}
