import 'package:flutter/material.dart';

/// MyPage "앱 정보" — 정보 제공처·약관류·버전 정보를 모아 두는 카테고리 목록.
/// 2026-09-17 사용자 지침으로 "고객센터" 메뉴는 삭제하고 이 목록으로 대체했다.
///
/// 2026-09-19: "서비스 소개" 항목은 제거하고, 버전 정보/정보 제공처/개인정보 처리방침/
/// 이용약관 네 항목 모두 실제 내용을 채웠다(사용자 지침).
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  static const _categories = [
    '버전 정보',
    '정보 제공처',
    '이용약관',
    '개인정보 처리방침',
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

  // "최신 버전"은 서버에 실제로 물어본 결과가 아니라 정적 안내 문구다 — 이 프로젝트는
  // 배포 버전이 하나뿐이고 업데이트·버전 체크 인프라가 없어서, 지금
  // 유일한 버전이 곧 최신 버전이다. 추후 앱스토어 배포로 버전이 여러 개 생기면
  // package_info_plus 등으로 동적 조회와 실제 최신 버전 비교 로직이 필요해진다.
  // 2026-09-19: 버전 문자열 자체는 검은 글씨로 강조하도록 _buildSections()의
  // 제목(굵게·검정) 자리에 넣는다.
  static const List<List<String>> _versionSections = [
    [_appVersion, '현재 최신 버전을 사용하고 계세요.'],
  ];

  // 이 앱이 실제로 연동해 쓰는 외부 데이터·서비스 출처. 카카오 로그인은 인증 수단이지
  // 정보 제공처가 아니라서 이 목록에 넣지 않는다. 2026-09-19: 각 카테고리명(관광 정보·
  // 날씨 정보 등)을 검은 글씨로 강조하도록 _buildSections()의 제목 자리에 넣는다.
  static const List<List<String>> _sourceSections = [
    ['관광 정보 · 방문 집중률 예측', '출처: ⓒ 한국관광공사 (공공데이터포털)'],
    ['날씨 정보', '출처: ⓒ Open-Meteo'],
    ['AI 현장 브리핑', '제공: Google Gemini'],
    ['지도', '제공: MapTiler'],
  ];

  static const String _placeholderBody = '준비 중입니다.\n내용은 곧 채워질 예정이에요.';

  // 2026-09-19: 일반적인 약관 템플릿이 아니라 이 앱이 실제로 수집·저장·전송하는
  // 항목만 코드를 근거로 확인해 채웠다(kakao_auth.py/user.py/presence.py/gemini.py 등).
  // 회사명·사업자번호 같은 운영자 식별 정보는 이 프로젝트에 존재하지 않아 넣지 않았고,
  // 문의처는 사용자가 직접 지정한 이메일을 쓴다.
  static const List<List<String>> _privacySections = [
    [
      '1. 수집하는 개인정보 항목',
      '카카오 로그인 시에는 카카오 회원번호(고유 식별자)만 수집합니다. 닉네임·프로필사진·이메일은 카카오로부터 수집하지 않습니다.\n'
          '서비스 이용 중에는 이용자가 직접 입력한 앱 내 닉네임, 현장 제보·질문·답변 내용을 수집합니다.\n'
          'GPS 좌표는 저장하지 않습니다 — 관광지까지의 거리를 계산하는 데만 순간적으로 쓰이고, 현장 인증 결과(거리값)만 24시간 보관 후 자동 삭제됩니다.',
    ],
    [
      '2. 수집 목적',
      '회원 식별과 로그인 유지, GPS 현장 인증(반경 판정), 현장 제보·질문·답변 서비스 제공, Credit·뱃지 게이미피케이션, AI 브리핑 생성을 위해 이용합니다.',
    ],
    [
      '3. 보유 및 이용 기간',
      '로그인 세션은 30일간 유지되며 자동 만료됩니다.\n'
          '현장 인증 기록(거리값)은 24시간 후 자동 삭제됩니다.\n'
          '제보·질문·답변·Credit 내역은 탈퇴 전까지 보관합니다. 현재 앱 내 탈퇴 기능은 제공하지 않으며, 삭제를 원하시면 아래 문의처로 요청해 주세요.',
    ],
    [
      '4. 제3자 제공 및 처리위탁',
      '개인정보를 원칙적으로 제3자에게 제공하지 않습니다.\n'
          '다만 AI 브리핑 생성을 위해 이용자가 작성한 제보 코멘트가 Google Gemini(AI)로 전송될 수 있습니다.\n'
          '카카오는 로그인 시 회원번호 확인 목적으로만 연동되며, 그 외 개인정보를 주고받지 않습니다.\n'
          '별도의 분석·광고 도구는 사용하지 않습니다.',
    ],
    [
      '5. 이용자의 권리와 행사 방법',
      '현재 앱 내 자동 탈퇴·삭제 기능은 제공하지 않습니다.\n'
          '개인정보 열람·정정·삭제를 원하시면 아래 문의처로 요청해 주시면 처리해 드립니다.',
    ],
    [
      '6. 문의처',
      '이메일: ktj518@naver.com',
    ],
  ];

  // 2026-09-19: 실제로 제공하는 기능·정책(GPS 반경, Credit 적립 규칙, 콘텐츠 길이 제한 등)만
  // 근거로 채웠다. 자동화된 신고·제재 시스템은 없어서(function.md §5, reviews/content_flags
  // 미구현) 3절에서 이 점을 정직하게 밝히고, 위반 처리는 문의를 통한 수동 대응으로 안내한다.
  static const List<List<String>> _termsSections = [
    [
      '1. 목적',
      '이 약관은 LiveSpot(이하 "서비스")의 이용조건과 이용자·운영자의 권리·의무를 정합니다. 서비스는 상시적인 운영을 보장하지 않습니다.',
    ],
    [
      '2. 이용계약의 성립',
      '카카오 로그인을 통해 회원가입이 이루어지며, 앱 내에서 직접 설정한 고유 닉네임으로 서비스를 이용합니다.\n'
          '관광지 정보 조회, 지도, 날씨, 혼잡도, AI 브리핑, 질문 조회는 비로그인 상태에서도 이용할 수 있습니다. 현장 제보·질문 작성·답변·북마크 등 참여 기능은 로그인이 필요합니다.',
    ],
    [
      '3. 이용자의 의무와 금지행위',
      '이용자는 GPS 위치를 허위로 조작하거나 실제로 방문하지 않은 장소에 제보·답변을 등록하는 등 서비스의 신뢰도를 해치는 행위를 해서는 안 됩니다.\n'
          '타인을 사칭하거나, 욕설·광고·저작권 침해 등 부적절한 내용을 게시해서는 안 됩니다.\n'
          '제보 코멘트는 30자, 질문·답변은 각 200자 이내로 작성해야 합니다.\n'
          '현재 자동화된 신고·제재 시스템은 운영하지 않으며, 위반 사실이 확인되면 운영자가 문의처를 통해 접수된 내용을 바탕으로 게시물을 제한하거나 삭제할 수 있습니다.',
    ],
    [
      '4. Credit 및 뱃지 운영정책',
      '현장 제보 등록 시 10 Credit, 질문에 대한 답변 등록 시 5 Credit이 적립됩니다(질문 작성은 적립 대상이 아닙니다). 같은 장소에서는 하루 최대 3건까지만 적립됩니다.\n'
          '누적 Credit에 따라 새싹~마스터 5단계 뱃지가 자동으로 부여됩니다.\n'
          'Credit과 뱃지는 서비스 내 게이미피케이션 요소이며, 현금이나 다른 재화로 교환할 수 없습니다. 부정한 방법으로 적립된 Credit은 회수될 수 있습니다.',
    ],
    [
      '5. 서비스의 변경·중단 및 면책',
      '서비스 내용은 예고 없이 변경되거나 중단될 수 있습니다.\n'
          '관광 정보·날씨·집중률 예측·AI 브리핑은 한국관광공사·Open-Meteo·Google Gemini 등 외부 서비스에서 제공받으며, 그 정확성을 운영자가 보장하지 않습니다.',
    ],
    [
      '6. 계약 해지 및 문의처',
      '현재 앱 내 자동 탈퇴 기능은 제공하지 않습니다. 탈퇴 또는 계정 삭제를 원하시면 아래 문의처로 요청해 주세요.\n'
          '이메일: ktj518@naver.com\n'
          '시행일: 2026년 9월 19일',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _sections != null ? _buildSections(_sections!) : _buildPlainBody(),
      ),
    );
  }

  List<List<String>>? get _sections => switch (title) {
        '버전 정보' => _versionSections,
        '정보 제공처' => _sourceSections,
        '개인정보 처리방침' => _privacySections,
        '이용약관' => _termsSections,
        _ => null,
      };

  Widget _buildPlainBody() {
    return Text(
      _placeholderBody,
      textAlign: TextAlign.left,
      style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.6),
    );
  }

  Widget _buildSections(List<List<String>> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          Text(
            section[0],
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            section[1],
            style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.6),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
