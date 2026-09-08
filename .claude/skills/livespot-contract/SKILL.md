---
name: livespot-contract
description: "LiveSpot 백엔드-프론트 경계면 정합성을 검증한다. FastAPI 응답 필드와 Flutter fromJson이 읽는 JSON 키를 양쪽 동시에 대조하고, 실제 서버를 띄워 curl 응답 키까지 확인한다. 'API 연동 확인', '값이 null로 나온다', '화면이 비어 있다', '목록이 안 뜬다', '필드명 맞는지 확인', '경계면 검증', 'QA', '정합성 점검', '스키마 바꿨는데 앱도 맞나' 같은 요청에 반드시 이 스킬을 사용할 것. 백엔드나 프론트 어느 한쪽을 수정한 뒤에는 요청이 없어도 이 스킬로 확인한다. 후속 재검증에도 동일하게 적용한다."
---

# LiveSpot 경계면 정합성 검증

LiveSpot의 실제 버그는 거의 전부 경계면에서 났다. 백엔드도 정상, 프론트도 정상, 그런데 화면은 비어 있었다. **한쪽만 읽는 검증으로는 절대 못 잡는다.**

Dart는 `json['content_id'] as String?`처럼 동적 캐스팅을 하므로 컴파일러가 키 오타를 잡아주지 않는다. **`flutter analyze` 통과는 정상 동작의 증거가 아니다.**

## 검증 절차

### 1단계 — 자동 대조 (번들 스크립트)

```
./livespot_backend/venv/Scripts/python.exe .claude/skills/livespot-contract/scripts/contract_diff.py
```

Pydantic 응답 필드와 Dart `json['키']`를 문자 단위로 대조해 4종 결함을 찾는다:

| 코드 | 의미 |
|---|---|
| `MISSING` | Dart가 읽는 키가 서버 응답에 없음 → 런타임 `null` (`null명 \| null건` 계열 버그) |
| `UNREAD` | 서버가 보내는데 Dart가 안 읽음 → 의도적 미사용인지 누락인지 판정 필요 |
| `NULLABLE` | `Optional` 필드를 Dart가 non-null 캐스팅 → 캐스트 예외 |
| `UTC` | naive UTC `datetime`인데 Dart에 `Z` 보정 없음 → 9시간 오차 |

짝을 못 찾으면 `--pair Dart=PydanticClass`로 지정한다. 매칭은 이름이 아니라 **읽는 키의 중첩도**로 결정되므로, 매칭 실패는 대개 "서버 응답이 없는 로컬 전용 모델"이라는 뜻이다.

### 2단계 — 실행 검증 (생략 불가)

`livespot-run` 스킬로 서버를 띄우고 **실제 응답 JSON을 본다.** 1단계는 정적 대조일 뿐이다 — `response_model` 필터링, `exclude_none`, 직렬화 설정 때문에 정의와 실제 응답이 다를 수 있다.

```bash
curl -s http://127.0.0.1:8000/api/live/hotspots | python -c "import sys,json; d=json.load(sys.stdin); print(sorted(d[0].keys()) if d else 'EMPTY')"
```

출력된 키 목록을 Dart `fromJson`과 대조한다. 쓰기 엔드포인트는 실제로 한 건 등록해 GPS·권한 분기까지 확인한다.

이어서 `cd livespot_app && flutter analyze` — 경고 포함 0건.

`flutter run`은 하지 않는다. 앱 구동 확인은 사용자가 한다.

### 3단계 — 스크립트가 못 잡는 것 (수동 확인)

스크립트는 `lib/models/`의 `fromJson`만 본다. 아래는 직접 양쪽을 열어 확인한다.

**경로 · 등록**
- `api_service.dart`의 `_dio.get/post` 경로 = `/api` + `router.py` prefix + 라우터 경로
- 새 라우터가 `app/api/router.py`에 `include_router`로 등록됐는가 (누락 시 404)
- 리스트 응답을 Dart가 `List<dynamic>`으로, 객체 응답을 `Map`으로 받는가

**모델을 거치지 않는 응답**
- `fetchSpotDetail` 처럼 `Map<String, dynamic>`을 그대로 반환하는 메서드는 스크립트 대상이 아니다. 화면에서 `data['키']`를 어떻게 꺼내는지 직접 대조한다

**화면 견고성**
- 신규·수정된 모든 `FutureBuilder`가 `snapshot.hasError`를 별도 분기하는가
- 에러 상태와 빈 상태의 화면이 서로 다른가

**상수 동기화**
- `config.py`와 `constants.dart`의 짝 값이 일치하는가 (`LIVE_WINDOW_HOURS` ↔ `liveWindowHours`)
- 어긋나면 **어느 쪽이 실제로 쓰이는 값인지 먼저 추적하라.** 죽은 상수는 "불일치"가 아니라 "미사용, 삭제 권고"로 보고한다 — `constants.dart::gpsVerificationRadius = 500`은 서버의 150과 다르지만 판정은 서버가 하므로 앱 값은 쓰이지 않는다

**상태 문자열**
- Dart의 `== 'ACTIVE'` 비교 대상이 서버 `Literal["ACTIVE","EXPIRED"]`에 실재하는가
- 서버가 낼 수 없는 값으로 분기하는 죽은 코드가 없는가

**정책 준수** (`_workspace/01_spec.md` 2절 대조)
- 확정 정책의 각 문장이 코드에 실제로 구현됐는가
- 권한 제약이 **서버에서 재검증**되는가 (클라이언트 상태만 믿는 곳이 없는가)
- "불가"로 명시된 동작의 UI 진입점이 아예 존재하지 않는가 — 조건문으로 숨긴 것은 통과가 아니다

## 점진 검증

전체 완성 후 1회 검증하면 경계면 불일치가 후속 모듈로 전파된 뒤에야 발견된다. **엔드포인트 하나가 완성되면 그 즉시 해당 엔드포인트 + 대응 Dart 코드만 검증한다.** 짝이 아직 없으면 "대기"로 기록하고 짝이 생길 때 검증한다.

## 판정 원칙

- **어느 쪽을 고칠지는 규약이 정한다.** 응답은 snake_case가 정답이다. 서버가 규약을 어겼으면 서버를, 서버가 규약대로인데 Dart가 다른 키를 읽으면 Dart를 고친다.
- **확인하지 못한 항목을 통과로 기록하지 않는다.** 리포트에 "미검증"란을 두고 이유를 적는다.
- **증거 없이 지적하지 않는다.** curl 실제 응답이나 코드 인용을 붙인다. 추측은 상대의 시간을 쓴다.
- 지적은 **파일:라인 + 수정 방법**까지 적어 보낸다. "불일치가 있습니다"만 보내면 상대가 다시 찾아야 한다.

## 알려진 버그 패턴

과거 실제로 발생한 결함의 증상·원인·재발 방지책은 `references/bug-patterns.md`를 읽어라. 증상만 보고 원인을 짐작하기 전에 이 표를 먼저 확인하면 대부분 바로 특정된다.
