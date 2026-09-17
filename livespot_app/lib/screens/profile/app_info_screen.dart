import 'package:flutter/material.dart';

/// MyPage "앱 정보" — 서비스 소개·데이터 출처·약관류·버전 정보를 모아 두는 카테고리
/// 목록. 2026-09-17 사용자 지침으로 "고객센터" 메뉴는 삭제하고 이 목록으로 대체했다.
///
/// 내용은 지금 채우지 않는다 — 페이지 뼈대만 먼저 만들고, 각 항목의 실제 텍스트는
/// 추후 별도로 채워 넣을 예정이다(사용자 지침). 그래서 [_AppInfoDetailScreen]은 전부
/// 같은 "준비 중" 플레이스홀더를 보여준다. 버전 정보만 `pubspec.yaml`의 실제 버전을
/// 그대로 보여준다 — 이건 지금도 알 수 있는 값이라 비워둘 이유가 없다.
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  static const _categories = [
    '서비스 소개',
    '데이터 출처',
    '이용약관',
    '개인정보 처리방침',
    '버전 정보',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(title: const Text('앱 정보')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final title = _categories[index];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: ListTile(
              title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right, color: Colors.grey[300]),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => _AppInfoDetailScreen(title: title)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AppInfoDetailScreen extends StatelessWidget {
  final String title;

  const _AppInfoDetailScreen({required this.title});

  static const String _appVersion = 'LiveSpot v1.0.0'; // pubspec.yaml version: 1.0.0+1

  @override
  Widget build(BuildContext context) {
    final isVersion = title == '버전 정보';
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            isVersion ? _appVersion : '준비 중입니다.\n내용은 곧 채워질 예정이에요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5),
          ),
        ),
      ),
    );
  }
}
