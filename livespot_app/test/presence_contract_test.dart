import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livespot_app/models/live_status.dart';
import 'package:livespot_app/models/verify_location_result.dart';

/// 기능 6(현장 사용자 수 집계)의 경계면 회귀 테스트.
///
/// 아래 JSON은 **실제로 로컬 백엔드(127.0.0.1:8000)에서 받은 응답 원문**이다
/// (`_workspace/02_backend_contract.md`와 동일한 페이로드). 손으로 지어낸 샘플이 아니라
/// 서버가 보낸 그대로여야 의미가 있다 — 서버가 키 이름을 바꾸면 이 테스트가 먼저 깨진다.
void main() {
  group('VerifyLocationResult.fromJson', () {
    test('반경 내: presence 등록 + 대기 질문 동봉', () {
      const raw = '''
{"verified":true,"distance_m":0.0,"threshold_m":150,
 "message":"현장 인증에 성공했습니다.","presence_registered":true,
 "pending_questions":[{"id":"acaa2cb8-be79-4207-8693-95ae1c5cdd28",
   "user_id":"seed_user_02","user_nickname":"테스트유저02","spot_content_id":"126508",
   "content":"presence smoke - line is long?","status":"ACTIVE","answer_count":0,
   "created_at":"2026-09-09T07:03:30.720461","expires_at":"2026-09-09T09:03:30.720461",
   "answers":[]}]}''';

      final result = VerifyLocationResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      expect(result.verified, isTrue);
      expect(result.presenceRegistered, isTrue);
      expect(result.pendingQuestions, hasLength(1));
      // pending_questions 원소가 기존 Question 모델로 그대로 파싱되는지 — 새 모델을
      // 만들지 않았다는 계약(02_backend_contract 1절)이 실제로 성립하는지 확인한다.
      expect(result.pendingQuestions.first.content, 'presence smoke - line is long?');
      expect(result.pendingQuestions.first.userNickname, '테스트유저02');
      expect(result.pendingQuestions.first.answerCount, 0);
      // 서버는 타임존 없는 UTC를 보낸다. Z 보정 없이 파싱하면 9시간 어긋난다.
      expect(result.pendingQuestions.first.createdAt.isUtc, isTrue);
    });

    test('반경 밖: 403이 아니라 200 + false/빈 배열 — 에러가 아니다', () {
      const raw = '''
{"verified":false,"distance_m":10640.462479160604,"threshold_m":150,
 "message":"현재 위치에서 10640m 떨어져 있어요. 관광지 반경 150m 이내에서만 인증할 수 있습니다.",
 "presence_registered":false,"pending_questions":[]}''';

      final result = VerifyLocationResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      expect(result.verified, isFalse);
      expect(result.presenceRegistered, isFalse);
      expect(result.pendingQuestions, isEmpty);
      // 데모 우회와 무관하게 distance_m은 언제나 실제 거리다.
      expect(result.distanceM, closeTo(10640.46, 0.01));
    });
  });

  group('LiveStatus.fromJson', () {
    test('onsite_user_count를 읽는다', () {
      const raw = '''
{"content_id":"126508","is_live":false,"recent_report_count":0,"onsite_user_count":1,
 "current_crowdedness":null,"current_waiting_time":null,"current_parking_status":null,
 "last_report_at":null}''';

      final status = LiveStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      expect(status.onsiteUserCount, 1);
      expect(status.recentReportCount, 0);
    });

    test('신호가 없는 관광지는 0이다 (null이 아니다)', () {
      const raw = '''
{"content_id":"126509","is_live":false,"recent_report_count":0,"onsite_user_count":0,
 "current_crowdedness":null,"current_waiting_time":null,"current_parking_status":null,
 "last_report_at":null}''';

      final status = LiveStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      // 0("아무도 없었다")과 조회 실패는 앱에서 서로 다른 화면이어야 한다.
      // 모델 단계에서는 0이 정상값으로 들어오는지만 확인한다.
      expect(status.onsiteUserCount, 0);
    });
  });
}
