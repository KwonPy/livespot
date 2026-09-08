---
name: livespot-flutter
description: "LiveSpot Flutter 웹앱에 화면·기능을 추가·수정하는 표준 절차. Dart 모델 fromJson 작성, ApiService 호출 메서드 추가, FutureBuilder 에러 분기, 위젯·화면 구성, Riverpod 상태를 다룬다. livespot_app/ 하위를 건드리는 모든 작업 — '화면 만들어', '앱에 연결', '위젯 추가', '모델 추가', 'UI 수정', '프론트 고쳐줘' — 에 반드시 이 스킬을 사용할 것. 후속 작업(화면 수정, 서버 응답 필드 추가에 따른 앱 반영, UI 버그 수정)에도 동일하게 적용한다. 단, '목록이 비어 보인다'·'값이 null이다'처럼 서버 연동이 의심되는 증상은 원인이 앱이 아닐 수 있으므로 livespot-contract로 먼저 확인한다."
---

# LiveSpot Flutter 구현 절차

대상은 **웹(Chrome)**이다. 앱은 계산하지 않고 서버가 준 값을 그린다.

## 절대 규칙 3가지

1. **`fromJson`은 snake_case 키를 읽는다.** 서버가 snake_case로 응답한다. Dart 필드명만 camelCase다.
2. **모든 `FutureBuilder`는 `hasError`를 별도 분기한다.** 아래 참조.
3. **조회 실패는 예외로 전파한다.** 빈 리스트로 삼키면 "0건"과 "실패"가 구분되지 않는다.

## 작업 순서

### 1단계 — 계약 확인

`_workspace/02_backend_contract.md`의 **실제 curl 응답 JSON**을 읽는다. Pydantic 정의만 보고 짐작하지 않는다. 계약이 아직 없으면 `backend-builder`에게 요청하고, 그동안 계약 무관한 레이아웃 작업을 진행한다.

### 2단계 — 모델 (`lib/models/{name}.dart`)

클래스당 파일 하나. `json['...']`의 키를 curl 결과와 **문자 단위로 대조**한다.

```dart
class Thing {
  final String contentId;        // Dart 필드는 camelCase
  final String? spotAddress;     // 서버가 Optional이면 반드시 nullable
  final int? reportCount;        // 조건부 필드도 nullable
  final DateTime? lastReportAt;

  factory Thing.fromJson(Map<String, dynamic> json) {
    return Thing(
      contentId: json['content_id'] as String,        // JSON 키는 snake_case
      spotAddress: json['spot_address'] as String?,   // Optional은 as X? 로 캐스팅
      reportCount: json['report_count'] as int?,
      lastReportAt: json['last_report_at'] == null
          ? null
          : _parseUtc(json['last_report_at'] as String),
    );
  }

  // 서버는 naive UTC를 보낸다. Z를 붙이지 않으면 로컬 시각으로 오인해 9시간 어긋난다.
  static DateTime _parseUtc(String value) {
    final hasTz = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    return DateTime.parse(hasTz ? value : '${value}Z');
  }
}
```

숫자는 `(json['x'] as num?)?.toDouble()`로 받는다. JSON의 정수/실수 구분이 서버 값에 따라 달라지므로 `as double`은 깨진다.

서버가 필수로 선언한 필드를 `?? 기본값`으로 받지 마라. 실패가 조용히 숨는다.

### 3단계 — ApiService (`lib/services/api_service.dart`)

위젯에서 `Dio`를 직접 쓰지 않는다. 싱글턴 + 테스트유저 헤더 인터셉터를 타야 한다.

```dart
/// 조회 실패는 (결과 0건과 구분할 수 있도록) 예외를 던진다.
Future<List<Thing>> fetchThings(String contentId) async {
  final response = await _dio.get('/things', queryParameters: {'content_id': contentId});
  if (response.statusCode == 200) {
    final List<dynamic> data = response.data;
    return data.map((json) => Thing.fromJson(json)).toList();
  }
  throw Exception('Failed to fetch things: ${response.statusCode}');
}
```

쓰기 실패는 서버가 준 메시지를 그대로 담아 던진다. GPS 범위 밖 거부 메시지("현재 위치에서 320m 떨어져 있어요...")가 사용자에게 그대로 보여야 유용하다.

```dart
} on DioException catch (e) {
  final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
  throw Exception(detail ?? '등록에 실패했어요');
}
```

경로는 `AppConstants.apiBaseUrl`(`http://127.0.0.1:8000/api`) 뒤에 붙는다. 메서드에는 `/api`를 다시 쓰지 않는다.

### 4단계 — 화면 · 위젯

`FutureBuilder`는 반드시 세 상태를 구분한다:

```dart
FutureBuilder<List<Thing>>(
  future: _future,
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SkeletonLoader();
    }
    if (snapshot.hasError) {
      return _errorBanner(snapshot.error);   // 빨간 배너 + 원문 메시지
    }
    final items = snapshot.data ?? [];
    if (items.isEmpty) {
      return _emptyState();                  // 회색 안내 문구
    }
    return _list(items);
  },
)
```

`final items = snapshot.data ?? [];`만 쓰면 네트워크 실패·타임아웃·스키마 불일치가 전부 "데이터가 없어요"로 보인다. HOT SPOTS가 안 뜬다는 신고를 받고 정상인 백엔드를 몇 시간 뒤진 원인이 정확히 이것이다.

`future`는 `initState`나 필드에서 한 번 만든다. `build` 안에서 만들면 리빌드마다 재호출된다.

### 5단계 — `flutter analyze`

경고를 포함해 0건이어야 한다. 경고를 남기고 넘기지 않는다.

## 제약은 구조로 강제한다

"이 화면에서는 답변 불가" 같은 규칙을 `if`로 숨기면 언젠가 새어나온다. **버튼이 존재할 수 없는 별도 위젯을 만든다.**

| 위젯 | 답변 | 용도 |
|---|---|---|
| `qa_section.dart` | 가능 | 상세페이지 · 내 현장 Q&A (GPS 인증 시) |
| `global_qa_list.dart` | 구조적으로 불가 | 전체 LIVE Q&A (읽기 전용) |
| `question_detail_sheet.dart` | 불가 | 질문 상세 (읽기 전용) |

같은 데이터를 권한이 다른 두 곳에서 보여줘야 하면 위젯을 나누는 쪽을 택한다.

## 공유 위젯의 모양을 한 화면만 바꿔달라고 하면

"상세페이지의 이 배지를 줄여줘" 같은 지시가 오면, 먼저 **그 위젯을 누가 또 쓰는지 grep한다.** 위젯 내부의 치수 상수를 직접 줄이면 지시에 없던 화면까지 조용히 같이 바뀐다 — 사용자는 그 화면을 확인하지 않으므로 한참 뒤에 발견된다.

**바꾸지 말아야 할 것은 기본값이다.** 새 플래그(`compact` 등)를 옵셔널로 받고 **기본값을 현행 그대로** 둔 뒤, 지시받은 호출부에서만 값을 넘긴다. 그러면 다른 호출부는 파일을 한 글자도 안 고쳐도 동작이 보존된다.

```dart
const WeatherBadge({super.key, required this.weather, this.compact = false});
...
size: compact ? 10 : 12,          // 분기는 삼항으로, 상수를 덮어쓰지 않는다
```

호출부가 하나뿐이라 플래그가 과해 보여도 마찬가지다 — 공유 위젯인지 아닌지가 기준이지 호출부 개수가 기준이 아니다.

## 계산하지 않는다

혼잡도 판정·랭킹·거리 임계값을 앱에서 다시 계산하지 않는다. 서버가 판정한 `display_level`·`basis`를 받아 색과 문구만 고른다. 앱에 계산이 필요해졌다면 서버 응답에 필드가 빠진 것이니 `backend-builder`에게 요청하라.

출처가 다르면 문구도 다르게 쓴다 — 제보 기반은 "여유/보통/혼잡", 집중률 예측은 "여유/보통/높음". 예측을 실측처럼 보이게 하지 않는다.

## 상수 (`lib/config/constants.dart`)

백엔드 `config.py`와 짝이 되는 값은 주석으로 대응 관계를 명시한다. 실제 판정을 서버가 하는 값(GPS 반경 등)은 앱에 중복으로 두지 않는다 — 두면 반드시 어긋난다.

## 화면이 안 바뀔 때

코드 버그로 단정하기 전에 **완전 재시작**을 먼저 해보라. 백엔드 스키마가 바뀐 뒤에는 hot reload만으로 반영되지 않는다. 그 다음 순서는: curl로 서버 응답 확인 → 응답 키와 `fromJson` 대조 → `hasError` 분기 존재 확인.
