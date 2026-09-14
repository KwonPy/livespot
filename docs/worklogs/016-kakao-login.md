# 카카오 로그인 (function.md 기능 1 / 구현 순서 9번째)

> 작업 기간: 2026-09-13(명세 판정) ~ 2026-09-14(구현·QA·마무리)
> 산출물 근거: `_workspace/01_spec.md` · `02_backend_contract.md` · `03_flutter_wiring.md` · `04_qa_report.md` + 실제 소스

---

## 1. 한 줄 요약

카카오 계정으로 로그인하면 서버가 우리 서비스 전용 출입증(JWT)을 발급해 주고, 그때부터 제보·질문·답변·북마크 같은 "쓰기" 기능이 열리며, 한 번 로그인하면 앱을 껐다 켜도 로그인 상태가 유지된다.

---

## 2. 왜 만들었는가

**이번 작업 전까지 이 프로젝트에는 "사용자"라는 개념이 사실상 없었다.**

지금까지 만든 기능 8개(제보, Q&A, 혼잡도, LIVE, 브리핑, Credit, 북마크, 알림)는 전부 "누가 했는가"를 기록하는데, 그 "누가"가 항상 `test_user`라는 가짜 사용자 한 명으로 고정돼 있었다. 백엔드의 `deps.get_current_user_id()`라는 함수 하나가 무조건 그 값을 돌려줬기 때문이다.

그래서:

- 제보를 누가 했는지, Credit이 누구 것인지 실제로는 구분되지 않았다.
- 아무나 `X-Test-User-Id`라는 헤더에 남의 id를 적어 보내면 그 사람 행세를 할 수 있었다(개발 모드 한정이지만 코드 주석에 명시돼 있던 상태).
- `function.md` 3장의 기능 1(회원가입·로그인)이 **구현 순서 9단계, 즉 마지막 단계**로 잡혀 있었다.

이번 작업은 그 가짜 사용자 자리에 **진짜 사용자**를 끼워 넣는 일이다. 바꿔 말하면 **완성돼 있던 기능 8개 전부가 회귀(regression) 위험 구간**이었다. 실제로 명세 판정관(spec-arbiter)의 총평 첫 문장이 이것이었다 — "이 기능은 `deps.py` 하나만 교체하면 된다는 문서의 서술과 달리, 실제로는 프로젝트 최초의 인증 계층 도입이다."

그리고 사용자가 이번 대화에서 추가로 요구한 것이 하나 더 있었다. **"로그인을 한번하면 상태가 유지되도록"** — 앱을 새로고침하거나 껐다 켜도 다시 로그인하지 않아도 되게 만드는 것. 이게 설계 판단(토큰 수명 30일, refresh 없음)을 결정했다.

---

## 3. 구현한 것

### 백엔드 (`livespot_backend/`)

- **`POST /api/auth/kakao`** — 앱이 카카오에서 받아 온 출입증(카카오 access token)을 보내면, 서버가 카카오에 직접 "이거 진짜 맞아?"라고 물어보고(P6), 맞으면 우리 서비스 전용 출입증(JWT)을 발급한다. 가입과 로그인이 같은 경로다.
- **`GET /api/auth/me`** — "이 출입증 아직 유효해?"를 확인하면서 내 정보(닉네임·프로필 이미지·Credit)를 받아 온다. 앱 시작 시 자동 로그인 복원에 쓴다.
- **`POST /api/dev/login-as/{user_id}`** — 개발/QA 전용. 카카오 없이 진짜 JWT를 발급받는다. `TEST_MODE=false`면 404.
- **`deps.py` 전면 교체** — "이 요청은 누구인가"를 판정하는 유일한 지점. 27개 라우터 호출부는 **한 줄도 안 바꿨다**.
- **WebSocket 인증 교체** — `?test_user_id=<uuid>` → `?token=<JWT>` (P13).
- **마이그레이션 `d3a91f7c2b58`** — `users.firebase_uid` → `auth_provider` + `provider_user_id`로 이름 정리, `profile_image_url` 컬럼 추가.
- **`firebase-admin` 제거 / `PyJWT` 추가**.

### 프론트 (`livespot_app/`)

- **카카오 JS SDK 팝업 로그인** — `web/index.html`에 카카오 SDK를 CDN으로 싣고, Dart에서 `dart:js`로 호출한다. Dart 패키지는 **하나도 추가하지 않았다**(MapTiler 지도를 붙일 때 쓴 방식 그대로).
- **로그인 상태 유지** — 발급받은 JWT를 `shared_preferences`(웹에서는 브라우저 localStorage)에 저장하고, 앱 시작 시 꺼내서 `GET /api/auth/me`로 확인한 뒤 로그인 상태를 이어간다.
- **인증 헤더 자동 주입** — `api_service.dart`의 인터셉터 한 곳에 `Authorization: Bearer` 한 줄을 추가했다. 40여 개 API 호출 메서드는 손대지 않았다.
- **로그인 유도 시트** (`login_required_sheet.dart`) — 위젯 하나를 만들어 **12곳**에서 재사용. 비로그인 사용자가 제보·질문·북마크 버튼을 누르면 "로그인이 필요해요" 바텀시트가 뜬다. 버튼을 숨기지는 않는다.
- **프로필 카드 + 로그아웃 메뉴** — 마이페이지에 닉네임·프로필 이미지를 띄우고, 로그아웃 메뉴 항목을 **신규로 추가**했다(기존에 없었다).
- **죽은 코드 정리** — `auth_service.dart` 전면 재작성, `providers/auth_provider.dart` 삭제.

### 이번에 만들지 않은 것

구글·이메일·애플 로그인(설계서가 "카카오 하나만"으로 확정), 네이티브 앱 로그인, 회원 탈퇴, 실제 Web Push/FCM, 신뢰도 등급 활용.

---

## 4. 동작 흐름

### 4-1. 로그인 (처음 또는 로그아웃 후)

```
사용자가 "카카오로 시작하기" 버튼 탭
→ Dart(kakao_login_bridge.dart)가 dart:js로 window.livespotKakaoLogin(jsKey) 호출
→ index.html의 자바스크립트가 Kakao.init(키) → Kakao.Auth.login({scope:'profile_nickname,profile_image'})
→ 카카오 로그인 팝업 창이 뜬다
→ 사용자가 동의하면 카카오가 access_token을 준다
→ Dart가 그 토큰을 받아 POST /api/auth/kakao 로 서버에 전달
→ [서버] kakao_auth.py 가 kapi.kakao.com에 2번 물어본다
     ① /v1/user/access_token_info : "이 토큰 우리 앱 것 맞아?" (app_id 대조)
     ② /v2/user/me                : 회원번호·닉네임·프로필이미지 가져오기
→ [서버] users 테이블에서 (auth_provider='kakao', provider_user_id=회원번호) 로 찾는다
     있으면 그 행을 쓰고(재로그인), 없으면 새 UUID로 행을 만든다 (upsert, P7)
→ [서버] auth_token.py 가 user_id를 담은 JWT를 HS256으로 서명 발급 (수명 30일)
→ LoginResponse(access_token, token_type, expires_at, is_new_user, user{...}) 응답
→ [앱] AuthUser.fromJson 으로 파싱
→ [앱] shared_preferences 에 'auth_access_token' 키로 저장
→ [앱] ApiService.accessToken = 토큰   (이제 모든 API 호출에 자동으로 붙는다)
→ [앱] app.dart가 신원 변경을 감지 → 알림 폴링·WebSocket 시작
→ 화면: 프로필 카드에 닉네임·프로필 이미지, 게이트 해제
```

### 4-2. 인증이 붙은 일반 요청

```
앱의 아무 API 호출 (예: POST /api/reports)
→ api_service.dart 인터셉터가 헤더를 붙인다
     accessToken이 있으면  → Authorization: Bearer <JWT>
     없고 testUserId가 있으면 → X-Test-User-Id: <id>   (개발 모드 전용)
     둘 다 없으면           → 아무것도 안 붙임
→ [서버] deps.get_current_user_id()
     ① Authorization 헤더가 있으면 → JWT 서명 검증 → DB에 그 사용자 행이 실제로 있는지 확인 → user_id
     ② 없고 TEST_MODE=true면 X-Test-User-Id → 그 테스트 사용자
     ③ 둘 다 없으면 → 401 "로그인이 필요합니다"
→ 라우터 핸들러는 user_id를 str로 받는다 (기존과 동일, 27곳 무변경)
```

### 4-3. 앱 재시작 (로그인 유지, P19)

```
브라우저 새로고침 / 앱 재실행
→ main() 이 runApp 보다 먼저 AuthService().restore() 를 await
→ shared_preferences 에서 'auth_access_token' 을 꺼낸다
     없으면 → 그냥 비로그인으로 시작 (네트워크 안 탐)
     있으면 → ApiService.accessToken 에 넣고 GET /api/auth/me 호출
          200 → 로그인 상태로 복원, AuthUser 갱신
          401 → 토큰 만료/무효 → 조용히 토큰 삭제하고 비로그인 (에러 배너 안 띄움, P20)
          네트워크 오류 → 토큰은 보존, 프로필 카드에 "다시 시도" 배너
→ runApp
```

`runApp`보다 **먼저** 기다리는 것이 중요하다. 앱이 그려진 뒤에 복원하면 첫 화면에 "로그인하세요"가 한 번 번쩍이고, 그보다 나쁘게는 알림 폴링·WebSocket이 비로그인으로 한 번 나갔다가(전부 401) 다시 붙는 창이 생긴다.

### 4-4. 로그아웃

```
마이페이지 > 로그아웃 메뉴 탭
→ 서버 호출 없음 (로그아웃 API를 일부러 안 만들었다, 9절 참고)
→ index.html의 livespotKakaoClearSession() → Kakao.Auth.logout()  (SDK가 들고 있는 카카오 토큰 폐기)
→ shared_preferences 에서 토큰 삭제 + ApiService.accessToken = null
→ app.dart가 신원이 null이 된 것을 감지 → NotificationService.stop() → resetForUserSwitch()
→ 알림 폴링·WS 정지, 배지 0으로 초기화 (AC7)
```

---

## 5. 주요 파일

### 백엔드

| 파일 | 역할 |
|---|---|
| `livespot_backend/app/api/auth.py` | **신규.** 카카오 로그인(`POST /auth/kakao`) · 내 정보(`GET /auth/me`) |
| `livespot_backend/app/api/deps.py` | **본문 전면 교체.** "이 요청은 누구인가"를 정하는 **백엔드 유일의 지점**. 27개 라우터가 전부 이것만 본다 |
| `livespot_backend/app/services/auth_token.py` | **신규.** JWT 발급(`create_access_token`) · 검증(`decode_access_token`). 서명 알고리즘은 HS256 고정 |
| `livespot_backend/app/services/kakao_auth.py` | **신규.** 카카오 서버에 토큰 검증·프로필 조회. 공용 `http_client.py` 재사용 |
| `livespot_backend/app/api/dev.py` | 테스트유저 목록 필터를 `auth_provider` 기반으로 교체 + `POST /dev/login-as/{user_id}` 신설 |
| `livespot_backend/app/api/notifications.py` | WebSocket 인증을 `?test_user_id=` → `?token=` 로 교체 |
| `livespot_backend/app/db/models/user.py` | `users` 테이블. `auth_provider` / `provider_user_id` / `profile_image_url` |
| `livespot_backend/app/models/schemas.py` | `KakaoLoginRequest`(549행) · `AuthUser`(561행) · `LoginResponse`(577행) |
| `livespot_backend/app/config.py` | `JWT_SECRET`(26행) · `AUTH_TOKEN_TTL_DAYS=30`(36행) · `KAKAO_APP_ID`(20행) |
| `livespot_backend/migrations/versions/d3a91f7c2b58_*.py` | `firebase_uid` 이름 정리 + `profile_image_url` 추가 + 기존 31행 백필 |
| `livespot_backend/scripts/seed_dev_data.py` | ⚠️ 명세의 영향 범위 표에 **없던 파일**인데 컬럼 rename으로 깨질 자리였다. 함께 고쳤다 |

### 프론트

| 파일 | 역할 |
|---|---|
| `livespot_app/web/index.html` | 카카오 JS SDK 로드 + `livespotKakaoLogin()` / `livespotKakaoClearSession()` 자바스크립트 함수 |
| `livespot_app/lib/services/kakao_login_bridge.dart` | **신규.** 위 자바스크립트 함수를 Dart에서 부르는 다리(`dart:js`). 팝업 취소를 구분하는 `KakaoLoginException.isCancelled` 포함 |
| `livespot_app/lib/services/auth_service.dart` | **전면 재작성.** 로그인 상태를 들고 있는 싱글턴(`ChangeNotifier`). `restore()` / `loginWithKakao()` / `logout()` / `setTestUserId()` |
| `livespot_app/lib/models/auth_user.dart` | **신규.** 서버 JSON → Dart 객체 변환(`fromJson`). 시각을 UTC로 바로잡는 `parseServerUtc` |
| `livespot_app/lib/models/login_result.dart` | **신규.** `LoginResponse` 전체(토큰 + 만료시각 + 신규가입여부 + user) |
| `livespot_app/lib/services/api_service.dart` | `accessToken` 정적 필드 + 인터셉터에 `Authorization` 주입 + auth 3종 메서드 |
| `livespot_app/lib/widgets/login_required_sheet.dart` | **신규.** 로그인 유도 바텀시트. `ensureLoggedIn()`(22행) / `promptLogin()`(36행) |
| `livespot_app/lib/main.dart` | `runApp` 전에 테스트유저 복원(kDebugMode 가드) + `AuthService().restore()` 대기 |
| `livespot_app/lib/app.dart` | 로그인 상태에 알림 폴링·WS 수명 주기를 **한 곳에서** 연결 |
| `livespot_app/lib/screens/profile/profile_screen.dart` | 로그인 버튼 연결 · 프로필 카드 · 로그아웃 메뉴 신규 · 메뉴 4종 게이팅 · 개발용 JWT 로그인 패널 |
| `livespot_app/lib/services/badge_tracker.dart` | 뱃지 승급 감지 기준 키를 로그인 `user_id` 기준으로 교체 |
| `livespot_app/lib/providers/auth_provider.dart` | **삭제** (import 0곳, 단순 bool이라 로그인 사용자를 담을 수 없었다) |

---

## 6. 핵심 코드 / 개념

### 6-1. JWT가 뭔가 — "위조할 수 없는 출입증"

로그인이 끝나면 서버가 문자열 하나를 준다. 겉보기엔 알파벳 뭉치지만 사실 점(`.`)으로 나뉜 세 덩어리다.

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 . eyJzdWIiOiI1NDliYjY0Yi05YTQy...In0 . nSBVMVMcEIEKiFxfNA6...
        ①어떤 방식으로 서명했나            ②내용물(누구인가, 언제 만료되나)      ③서명
```

②는 그냥 Base64로 인코딩된 JSON이라 **누구나 읽을 수 있다**(암호화가 아니다). 대신 ③ 서명이 있어서, 내용을 한 글자라도 바꾸면 서명이 안 맞아 서버가 거부한다. 서명에 쓰는 비밀키(`JWT_SECRET`)는 서버만 갖고 있다.

우리 토큰에 담는 내용물은 4개뿐이다.

```python
payload = {
    "sub": user_id,        # 누구인가 (우리 내부 UUID. 카카오 회원번호가 아니다 — P4)
    "iss": "livespot",     # 누가 발급했나
    "iat": int(now.timestamp()),        # 언제 발급됐나
    "exp": int(expires_at.timestamp()), # 언제 만료되나 (30일 뒤)
}
token = jwt.encode(payload, _secret(), algorithm="HS256")
```

검증할 때 `algorithms=["HS256"]`을 **명시적으로 고정한 것이 중요하다**. 생략하면 토큰 헤더에 적힌 알고리즘을 그대로 믿게 되는데, 공격자가 거기에 `alg: none`(서명 없음)을 적어 보내면 서명 검사를 건너뛰게 만들 수 있다. JWT의 대표적인 함정이다.

### 6-2. 판정 지점이 하나여야 하는 이유 (`deps.py`)

```python
async def get_current_user_id_optional(authorization, x_test_user_id, db) -> str | None:
    token = _extract_bearer(authorization)
    if token is not None:
        # ① Authorization이 있으면 여기서 끝. 실패해도 ②로 흘러가지 않는다
        return await resolve_user_id_from_token(db, token)

    if settings.TEST_MODE and x_test_user_id:
        # ② 개발 전용. 값을 그대로 믿지 않고 실제 존재하는 행인지 확인한다
        user = await db.get(User, x_test_user_id)
        if user is not None:
            return x_test_user_id

    return None  # ③ 비로그인
```

포인트 둘.

1. **①이 ②보다 반드시 먼저다.** 순서가 뒤집히면, 실제로 로그인한 사용자가 앱에 남아 있던 옛 테스트 헤더 때문에 남의 계정으로 동작한다 — **화면에는 내 닉네임이 뜨는데 제보는 test_user 이름으로 저장되는**, 원인을 찾기 가장 어려운 종류의 상태가 된다.
2. **무효한 토큰이 ②로 폴스루하지 않는다.** 토큰이 만료됐을 때 조용히 테스트 헤더로 대체되면 더 혼란스럽다. 그래서 `Authorization`이 있으면 결과가 실패여도 거기서 끝낸다.

그리고 서명 검증만으로 끝내지 않고 **DB에 그 사용자 행이 실제로 있는지까지 본다.** 서명이 맞아도 사용자가 지워졌으면 그 토큰으로 쓰기를 할 때 외래키(FK) 위반으로 500이 난다. 401이 정직하다.

### 6-3. 인터셉터 한 줄로 40개 API를 한꺼번에 인증시킨 것

Flutter에서 서버를 부르는 메서드가 40개쯤 있는데, 전부에 헤더를 붙이려면 40군데를 고쳐야 한다. 그런데 Dio(HTTP 라이브러리)에는 **모든 요청이 나가기 직전에 한 번 거쳐 가는 자리**가 있다. 이걸 인터셉터(interceptor, 가로채기)라고 한다.

```dart
final token = accessToken;
if (token != null) {
  options.headers['Authorization'] = 'Bearer $token';
} else if (testUserId != null) {
  options.headers['X-Test-User-Id'] = testUserId;
}
```

**둘 중 하나만 보낸다.** 둘 다 보내면 서버는 토큰을 택하지만(우선순위 ①>②), 요청만 봐서는 어느 쪽이 이겼는지 알 수 없어 위의 "화면엔 내 닉네임, 제보는 test_user" 같은 상황이 생겼을 때 원인 추적이 어려워진다. 앱과 서버의 우선순위를 같은 순서로 맞춰 두는 것이 요점이다.

이 자리가 원래부터 단일 지점으로 모여 있었던 덕분에(기능 13에서 테스트유저 헤더를 붙이려고 만들어 둔 자리), 프론트 인증 작업이 **한 곳 + 저장/복원**으로 끝났다.

### 6-4. 로그인 게이트는 보안이 아니라 UX다

```dart
if (!await ensureLoggedIn(context, actionLabel: '현장 제보')) return;
```

비로그인 사용자가 제보 버튼을 누르면 이 한 줄이 로그인 유도 바텀시트를 띄우고, 로그인하면 `true`를 돌려줘 원래 하려던 동작이 이어진다.

**이건 보안 경계가 아니다.** 앱 코드는 사용자가 얼마든지 우회할 수 있다. 실제로 막는 것은 **서버의 401**이고(AC2), 게이트는 "빨간 에러 대신 로그인 안내를 보여 주는" UX 장치일 뿐이다. 두 가지가 다 필요하다 — 게이트가 없으면 사용자에게 고장으로 보이고, 서버 401이 없으면 그냥 뚫린다.

게이트를 **GPS 권한 팝업보다 먼저** 두는 것도 규칙으로 정했다. 어차피 로그인 시트를 보게 될 사용자에게 위치 권한부터 요구하지 않기 위해서다.

### 6-5. 카카오 토큰을 한 번 더 확인하는 이유

`kakao_auth.py`가 카카오에 두 번 물어본다. `/v2/user/me`(프로필)만으로 충분해 보이는데 왜 `/v1/user/access_token_info`(앱 소유 확인)를 먼저 부르는가.

`/v2/user/me`는 **"이 토큰이 유효한가"만 보고 "어느 앱의 토큰인가"는 보지 않는다.** 그래서 그대로 두면 공격자가 **자기 카카오 앱**에 피해자를 로그인시켜 얻은 토큰을 우리 서버에 제시하는 것만으로 피해자 계정이 열린다. `app_id` 대조가 그 문을 닫는다.

그리고 이 모듈은 다른 외부 API 서비스(`weather.py`·`gemini.py`)와 **실패 정책이 반대다**. 그쪽은 읽기라서 실패하면 폴백 값을 돌려주지만, 여기는 인증이다 — "확인하지 못했으니 일단 통과"는 곧 아무나 남의 계정으로 로그인하는 문이 된다. 그래서 실패는 반드시 예외로 올린다.

또 **401과 502를 반드시 구분한다.** 카카오가 토큰을 거부한 것(401, 사용자가 다시 로그인하면 해결)과 카카오 서버에 닿지 못한 것(502, 몇 번을 눌러도 안 됨)은 사용자가 해야 할 행동이 다르다. 502를 401로 뭉개면 앱이 "다시 로그인하세요"를 띄우는데 사용자가 몇 번을 눌러도 되지 않는다.

---

## 7. 사용한 기술

| 기술 | 어디에 | 왜 |
|---|---|---|
| **PyJWT 2.9.0** | 백엔드 토큰 발급·검증 | 자체 JWT 방식(Q2-A)에 필요한 유일한 새 의존성. `firebase-admin`을 지웠으므로 의존성 순증은 0 |
| **카카오 JavaScript SDK v1** (`developers.kakao.com/sdk/js/kakao.js`) | `web/index.html` | 팝업 로그인(`Kakao.Auth.login`)이 v1의 API다. v2는 리다이렉트 중심이라 앱이 리로드된다 |
| **`dart:js`** | `kakao_login_bridge.dart` | Dart에서 `index.html`의 자바스크립트 함수를 호출. MapTiler 지도를 붙일 때 쓴 방식과 동일 |
| **`shared_preferences`** | 토큰 저장 | 이미 의존성에 있었다(테스트유저 id 저장에 쓰던 것). 웹에서는 브라우저 localStorage에 저장된다 |
| **Alembic `batch_alter_table`** | 마이그레이션 `d3a91f7c2b58` | SQLite는 컬럼 이름 변경을 직접 지원하지 않는다. batch 모드가 "새 테이블 만들고 복사하고 바꿔치기"를 대신 해 준다 |
| **`String.fromEnvironment`** | `constants.dart:22` `kakaoJsKey` | 카카오 JS 키를 코드에 적지 않고 빌드할 때 `--dart-define`으로 주입. `apiBaseUrl`이 쓰던 방식 그대로 |

**추가하지 않은 것**: Flutter 패키지 0개(`pubspec.yaml` 무변경), Firebase 프로젝트, refresh 토큰 인프라, 세션 저장소(Redis 등), CORS 변경.

---

## 8. 문제와 해결

### 8-1. F1 — LIVE 탭 "GPS 연동" 토글에만 게이트가 빠졌다

- **문제**: 비로그인 사용자가 LIVE 탭에서 "GPS 연동"을 켜면 GPS 권한 팝업이 먼저 뜨고, 그 다음 **빨간 에러 문구 "로그인이 필요합니다"**가 떴다. 로그인 유도 시트는 안 떴다.
- **원인**: 게이트를 붙일 지점 목록을 만들 때 이 토글이 빠졌다. 같은 파일(`live_screen.dart`)의 제보 FAB에는 게이트가 있는데 토글에만 없었다. 이 토글이 부르는 API 3개(`POST /reports/verify-location`, `GET /reports/me`, `GET /questions/me/answers`)가 전부 비로그인 401이다.
- **해결**: `_onToggleGps` 최상단, `setState`보다 **먼저** 게이트를 걸었다. **켜는 방향일 때만** — 끄는 동작까지 막으면 로그인이 풀린 뒤 토글을 되돌릴 수 없다.
  ```dart
  if (value && !await ensureLoggedIn(context, actionLabel: '현장 인증')) return;
  if (!mounted) return;
  setState(() => _isGpsVerified = value);
  ```
- **어떻게 찾았나**: QA가 게이트 지점 목록을 위에서부터 훑은 게 아니라, **쓰기 API를 부르는 모든 위젯을 역추적**했다. 위젯에서 API로 내려가는 방향이 아니라 API에서 위젯으로 올라가는 방향으로 세야 누락이 잡힌다.

### 8-2. F2 — 테스트유저 id에 `kDebugMode` 가드가 읽는 쪽에만 없었다

- **문제**: 테스트유저 드롭다운을 한 번이라도 쓴 브라우저에서는 **비로그인 UX를 두 번 다시 관찰할 수 없었다.** 이번 기능의 핵심 수용 기준(AC2 앱 쪽 동작, AC7)을 검증할 수단이 막힌 상태였다.
- **원인 둘**:
  1. `main.dart`가 저장된 테스트유저 id를 복원하는데 `kDebugMode` 가드가 없었다. 그 값을 **쓰는 쪽**(`profile_screen`의 드롭다운 UI)은 가드가 돼 있는데 **읽는 쪽**만 빠져 비대칭이었다. 그리고 그 값이 곧 `AuthService.hasServerIdentity`를 `true`로 만들어 **게이트 12곳을 전부 통과시킨다.**
  2. **`dev_test_user_id`를 지우는 코드가 프로젝트 전체에 없었다.** 드롭다운에 "선택 해제" 항목이 없었다.
- **해결**: `main.dart`의 복원을 `if (kDebugMode) { ... }`로 감싸고(주석에 이유를 길게 남겼다), 드롭다운에 테스트유저 해제 경로를 만들었다.
- **왜 위험했나**: 로컬 `localhost:8080`은 `flutter run`과 `flutter build web` 로컬 서빙이 **같은 origin**이라 localStorage가 실제로 겹친다. 릴리스 빌드에서도 이 값이 살아나면 "화면은 로그인하세요인데 게이트는 통과하고 모든 요청이 401로 떨어지는" 상태가 된다. 서버가 `TEST_MODE=false`에서 헤더를 무시하므로 보안 구멍은 아니지만, **원인을 찾기 가장 어려운 종류의 상태**다.

### 8-3. F3 — 뱃지 승급 감지가 로그인 사용자를 몰랐다

- **문제**: 같은 브라우저에서 카카오 계정 A로 쓰다가 B로 로그인하면, B가 원래 갖고 있던 등급을 **"방금 승급"으로 축하**하거나, 반대로 B의 진짜 승급이 **조용히 넘어갔다.**
- **원인**: `badge_tracker.dart`가 "마지막으로 본 뱃지 코드"를 저장하는 키를 `last_seen_badge_code:${ApiService.testUserId ?? 'default'}`로 만들고 있었다. 기능 9 전에는 신원 체계가 테스트유저 헤더 하나뿐이라 맞았는데, **로그인이라는 두 번째 신원 체계가 생겼는데 이 소비자가 갱신되지 않았다.** 로그인한 카카오 사용자는 전부 `…:default` 한 칸을 공유했다.
- **해결**: 신원 판정을 `app.dart`·서버 `deps.py`와 **같은 우선순위**(①로그인 `user_id` ②테스트유저 헤더)로 통일했다.
  ```dart
  static String _prefsKey() =>
      '$_prefsKeyPrefix:${AuthService().user?.userId ?? ApiService.testUserId ?? 'anonymous'}';
  ```

### 8-4. F4 — `.env`에 `JWT_SECRET`이 없어 서명키가 개발용 기본값이었다 (이번 대화에서 처리)

- **문제**: 서버를 띄울 때마다 `JWT_SECRET이 개발용 기본값 그대로입니다...` 경고가 떴다. 이 값이 알려지면 **임의의 `user_id`로 토큰을 위조할 수 있다.** `.env.example`에는 키 이름과 생성법이 적혀 있었지만 실제 `.env`에는 없었다.
- **원인**: `.env`는 `.gitignore` 대상이라 builder 에이전트가 채울 수 없고, `.env.example`에 항목을 추가하는 것과 실제 `.env`를 채우는 것은 **별개의 행위**다. 예시 파일만 고치고 넘어가면 경고 로그만 남은 채 검증이 꺼진 상태로 계속 동작한다.
- **해결** (2026-09-14, 리더 직접 처리):
  1. `python -c "import secrets;print(secrets.token_urlsafe(48))"`로 새 시크릿을 생성해 `.env`에 `JWT_SECRET=`으로 추가.
  2. 죽은 `KAKAO_API_KEY` 줄 삭제 — `config.py`에서 제거됐고 읽는 코드가 0곳이었다. 남겨두면 "어느 키인지 모를 값"이 다시 쌓인다.
  3. `KAKAO_APP_ID`는 사용자가 이미 채워 둔 상태였다.
- **실측 확인**: uvicorn 재기동 시 경고가 **더 이상 출력되지 않는다.** `POST /api/dev/login-as/<test>` → 200, `Authorization: Bearer garbage` → 401. 기존 동작 회귀 없음.
- ⚠️ 시크릿을 교체했으므로 **이전에 발급된 토큰은 전부 무효**다. 아직 실사용자가 없어서 지금 하는 편이 쌌다.

### 8-5. 명세의 영향 범위 표에 없던 파일이 깨질 뻔했다

- **문제**: `users.firebase_uid` 컬럼 이름을 바꾸는 마이그레이션이 `scripts/seed_dev_data.py`를 조용히 깨뜨릴 자리였다. 이 파일은 `_workspace/01_spec.md` 6절 영향 범위 표에 **없었다.**
- **원인**: 명세 판정 단계에서 `firebase_uid`를 grep했을 때 코드 파일은 잡았는데 `scripts/` 아래의 일회성 스크립트는 목록에 안 올랐다.
- **해결**: `auth_provider` 기반으로 함께 고치고 실제로 실행해 멱등 동작을 확인했다(users 0명 신규 / reports 16건 시간 갱신). 고치지 않았으면 다음 실행 때 `TypeError`로 죽어 **30명 QA 데이터 재생성이 막혔을 것**이다.

### 8-6. R1 — "v2 SDK에는 `Auth.login`이 없다"는 우려는 근거가 없었다

- **문제**: flutter-builder가 "카카오 JS SDK v2에는 팝업 로그인 API가 없을 수 있고, 그러면 백엔드에 `kakao_authorization_code` 확장 + `KAKAO_REST_API_KEY` + Redirect URI 등록이 새로 필요하다"는 위험을 올렸다. 이게 사실이면 백엔드 작업이 추가되고 계약 전제가 깨진다.
- **해결**: QA가 `index.html`이 싣는 **바로 그 URL의 실제 파일을 받아서** 확인했다(`GET https://developers.kakao.com/sdk/js/kakao.js` → 200, 205,743 bytes). 파일 안에 `Kakao.Auth.login`이 존재하고, `index.html`이 넘기는 파라미터 3개(`scope`·`success`·`fail`)가 전부 SDK의 허용 목록에 있으며, `doLogin`이 `openLoginPopup`으로 떨어진다 — **Q1-B가 전제한 팝업 동작 그대로**다.
- **결론**: 백엔드 추가 작업 없음. `index.html`의 방어 분기("이 SDK 버전에는 팝업 로그인이 없습니다")는 그대로 뒀다 — 카카오가 그 URL 뒤의 버전을 바꿀 수 있다.

### 배운 점 — 어디에 규칙으로 넣었나

이번 실패 4건 중 3건(F1·F2·F3)이 **"신원 체계가 하나에서 둘로 늘어날 때"** 생긴 같은 계열의 문제였다. 산문으로만 적어두면 다음에 안 읽히므로 일반화해서 `.claude/skills/livespot-contract/references/bug-patterns.md`에 실제 규칙으로 넣었다.

- **5-5. 요청 주체를 정하는 값이 둘 이상이 되면 — 소비자를 전수 열거해 우선순위를 통일한다** (F2·F3 일반화)
- **6-3. 새 게이트를 도입할 때는 게이트 지점이 아니라 보호 대상 API에서 역추적한다** (F1 일반화)
- **7절 배포·환경 표에 1행 추가**: 새 보안 설정값이 `.env.example`에만 추가되고 실제 `.env`가 비어 검증이 꺼진 채 동작 (F4 일반화)

---

## 9. 의사결정

**이 절이 이 일지의 본체다.** 이번 작업에서 실제로 막혔던 것은 코드가 아니라 판단이었다 — `function.md`의 확정안(Firebase 다리)이 근거를 잃었고, 명세에 없는 설계 결정(토큰 수명, 비로그인 쓰기 범위, 테스트유저 처리)이 6건이나 남아 있었다.

### 9-0. 사용자가 준 정책 (원문)

> 아래는 `_workspace/01_spec.md` 2-0절·2-0-1절을 **원문 그대로** 옮긴 것이다. 요약하지 않는다. 이 프로젝트에는 정책 전용 파일이 없으므로, 여기에 남기지 않으면 원문은 사라진다.

#### 2-0. 사용자 확정 (2026-09-13, 리더가 AskUserQuestion으로 확인)

> | # | 질문 | 확정 | 비고 |
> |---|---|---|---|
> | Q1 | 웹 로그인 방식 | **B. 카카오 JS SDK 팝업** | `web/index.html`에 JS SDK 로드, MapTiler 패턴 복제. 앱 리로드 없음 |
> | Q2 | 세션 유지 방식 | **A. 자체 발급 JWT + `Authorization: Bearer`** | `function.md:95` Firebase 다리는 폐기. CORS 무변경 |
> | Q4 | 카카오 앱 키 | **2026-09-14 재확인: 아직 미발급 상태였음(`.env`의 `KAKAO_API_KEY`가 빈 값).** 사용자가 지금 새로 발급받아 채우기로 함 | 사용자가 직접 `livespot_backend/.env`에 값을 채운다(채팅에 붙여넣지 않음). `.env.example`에 키 이름(`KAKAO_JS_KEY`/`KAKAO_REDIRECT_URI` 등 Q1-B 기준으로 필요한 것만)과 발급처 안내 주석만 백엔드 구현자가 채운다. **키가 없어도 착수 가능한 작업(JWT 발급/검증, `deps.py` 교체, `users` 마이그레이션, Flutter 로그인 상태관리)을 먼저 진행하고, 실제 카카오 연동(JS SDK 팝업 → 서버 검증) 종단 테스트는 키가 채워진 뒤 QA에서 확인한다** |
> | Q5 | 비로그인 쓰기 범위 | **C. 쓰기 전면 로그인 + 유도 시트** | `verify-location`·북마크 포함 전부 로그인 필수(AC2). 비로그인 사용자가 버튼을 누르면 로그인 유도 바텀시트 표시 |
> | — | (사용자 추가 요청) 로그인 상태 유지 | **로그인 1회 후 앱 재실행/새로고침에도 로그인 상태가 유지되어야 한다** | Q6(토큰 수명)과 직결. JWT를 `shared_preferences`에 저장해 앱 시작 시 복원(자동 로그인). 아래 P19 참조 |

#### 2-0-1. 로그인 상태 유지 (신규 확정 요구사항)

> | # | 정책 | 근거 |
> |---|---|---|
> | P19 | 로그인 성공 시 서버 JWT를 `shared_preferences`에 저장한다(`pubspec.yaml`에 이미 존재, `profile_screen.dart:115-116` 선례). 앱 시작 시(`main.dart`/`app.dart` 초기화 경로) 저장된 토큰이 있으면 `ApiService.accessToken`에 복원하고 `GET /api/auth/me`로 유효성을 확인해 로그인 상태를 이어간다 | 사용자 확정: "로그인을 한번하면 상태가 유지되도록" |
> | P20 | 복원한 토큰이 만료·무효(401)면 조용히 로그아웃 상태로 전환한다(에러 배너 없음) — 사용자가 마지막으로 로그인했던 사실은 유지하되 재로그인만 요구 | P19 + AC3(401) 일관성 |
> | P22 | **→ 2026-09-14 부분 폐기, 아래 변경 이력 참조 (`docs/worklogs/017-app-owned-unique-nickname.md` 9-1)** · **사용자 식별자(PK)는 여전히 내부 UUID(P4·P8)다. 닉네임은 화면 표시 전용이다** — 카카오 닉네임을 중복 허용 값으로 저장하고, 프로필 카드·제보/질문/답변 작성자 표시 등 "누구인지 보여주는" 모든 자리에 일관되게 쓴다. 닉네임을 식별/매칭 키로 쓰지 않는다(중복 허용, unique 제약 없음) | 사용자 확정(2026-09-13): "닉네임으로 사용자를 구별하자" = 표시 용도. `question.dart`/`report.dart`에 이미 `nickname` 필드가 있어 재사용 가능 |

#### 사용자가 채팅으로 준 문장 (반드시 원문 보존)

> **"로그인을 한번하면 상태가 유지되도록"**

> **"닉네임으로 사용자를 구별하자"**

⚠️ 두 번째 문장은 **해석이 갈리는 자리**였다. 글자 그대로 읽으면 "닉네임을 사용자 식별 키로 쓴다"가 되는데, 그러면 닉네임이 같은 두 사람이 같은 계정이 되고 닉네임을 바꾸면 활동 이력이 끊긴다(카카오 닉네임은 중복 허용이고 언제든 바뀐다). 그래서 **"누구인지 보여주는 값으로 닉네임을 쓴다"(표시 용도)**로 읽고 P22로 확정했다. 식별 키는 내부 UUID를 유지한다. 원문을 위에 그대로 남겨 둔 것은 이 해석이 나중에 틀렸다고 판명될 수 있기 때문이다.

---

### 9-1. `function.md`의 확정안을 폐기한 결정 — Firebase 다리

| | 내용 |
|---|---|
| **갈림길** | `function.md:95`는 "카카오 → 서버가 카카오에 확인 → **Firebase 토큰 발급**"을 확정안으로 적어 뒀고, `firebase-admin==6.5.0`이 이미 `requirements.txt`에 있었다. 그대로 따를 것인가, 자체 JWT로 갈 것인가 |
| **택한 것** | **자체 발급 JWT + `Authorization: Bearer`** (Q2-A, 사용자 승인) |
| **왜 다른 쪽을 버렸나** | ⓐ **Firebase가 필요했던 유일한 이유가 이미 사라졌다.** 그 이유는 FCM 푸시였는데, P21(최종 출품물은 모바일 웹서비스)과 기능 8의 P13(`push_subscriptions`를 FCM 전제 없이 채널 중립으로 설계)으로 범위 밖이 됐다. ⓑ **코드가 이미 이 방향으로 준비돼 있었다** — `main.py`의 CORS 주석이 "로그인 토큰은 쿠키가 아니라 Authorization 헤더로 전달되므로 credentials 불필요"라고 명시하고 있었다. ⓒ `firebase-admin`은 **import하는 파일이 0개**였고, Flutter `firebase_core`/`firebase_auth`는 `pubspec.yaml`에 주석 처리돼 있었다. Firebase를 지금 붙이면 프로젝트 생성 + 서비스 계정 키 관리 + Custom Token 발급 + Flutter 패키지 3개 부활이 필요한데, **인증 자체에는 기여가 없다**(카카오 검증은 어차피 우리 서버가 한다). 토큰 종류만 둘(카카오·Firebase)로 늘어 디버깅 경로가 하나 더 생긴다 |
| **주의** | 이건 **설계서의 "확정안" 문장을 폐기하는 판정**이라 판정관이 단독으로 결정하지 않고 사용자 승인을 받았다. 나중에 FCM이 정말 필요해지면 그때 Firebase를 얹어도 우리 `user_id` 체계는 그대로 유지된다(P4·P8) |

### 9-2. 세션을 쿠키로 하지 않은 결정

| | 내용 |
|---|---|
| **갈림길** | `HttpOnly` 쿠키 세션은 XSS로 토큰이 유출되지 않아 보안상 가장 강하다 |
| **택한 것** | `Authorization` 헤더 + 브라우저 저장소(localStorage) |
| **왜 다른 쪽을 버렸나** | `main.py`의 CORS가 `allow_origins=["*"]` + `allow_credentials=False`인데, 쿠키를 쓰려면 이걸 **명시적 origin 목록 + `allow_credentials=True`**로 바꿔야 한다. 게다가 프론트와 백엔드가 **서로 다른 Railway 도메인**이라 크로스 사이트 쿠키(`SameSite=None; Secure`)가 필요해지고, 브라우저의 3rd-party 쿠키 차단 정책에 정면으로 걸린다. 세션 저장소(DB 또는 Redis)도 새로 필요하다. **얻는 것에 비해 구조 변경이 너무 크다** |
| **대가** | 토큰이 `localStorage`에 있으므로 XSS가 있으면 유출된다. 이 앱은 사용자 입력을 HTML로 렌더링하는 자리가 없어 현재 위험은 낮지만, 알려진 대가로 남긴다 |

### 9-3. 토큰 수명 30일, refresh 토큰 없음

| | 내용 |
|---|---|
| **갈림길** | A. 30일 단일 토큰 / B. 1시간 access + 30일 refresh / C. 무기한 |
| **택한 것** | **A. 30일 단일 토큰, refresh 없음** (`config.py:36` `AUTH_TOKEN_TTL_DAYS=30`) |
| **왜 다른 쪽을 버렸나** | B는 표준적이고 유출 노출 창이 짧지만, **refresh 엔드포인트 + 401 자동 재시도 인터셉터 + refresh 회전**이 전부 새 작업이다. 특히 **이 앱은 7초 알림 폴링과 WebSocket 재연결이 동시에 도는 구조**라 동시 다발 401에서 refresh가 중복 호출되는 경합을 따로 막아야 한다. 출품 규모(사용자 수 명, 개인정보는 카카오 닉네임·프로필 이미지뿐, 결제·민감정보 없음)에서 이 복잡도는 순수 비용이다. C는 나중에 만료를 도입할 때 기존 토큰 처리 정책이 또 필요하다 |
| **사용자 요구와의 연결** | **"로그인을 한번하면 상태가 유지되도록"** 이 요구와 직접 부합한다. 30일이면 앱을 다시 열어도 재로그인이 필요 없고, 출품 시연에서 매번 로그인하지 않아도 된다 |
| **대가** | 토큰이 유출되면 30일간 유효하고, **로그아웃은 클라이언트가 저장된 토큰을 지우는 것일 뿐 서버가 무효화하지 못한다.** 값을 `config.py` 한 곳에 근거 주석과 함께 상수로 뒀으므로, 나중에 B로 올릴 때 바꿀 지점이 한 곳이다(이 프로젝트가 질문 TTL 2시간, presence 30분, LIVE 2시간에 쓴 방식과 동일) |

### 9-4. 로그아웃 엔드포인트를 **일부러 만들지 않았다**

| | 내용 |
|---|---|
| **갈림길** | `POST /auth/logout`을 만들어 200만 돌려줄 것인가, 아예 안 만들 것인가 |
| **택한 것** | **만들지 않았다** |
| **왜 다른 쪽을 버렸나** | 9-3(refresh 없는 단일 토큰)에서 서버는 발급된 토큰을 무효화할 수단이 없다. 그런데도 `POST /auth/logout`이라는 이름의 엔드포인트가 있으면, **그 이름을 본 다음 사람이 "서버에서 세션이 끊겼다"고 착각한다.** 실제로 하는 일이 없는데 하는 것처럼 보이는 API가 가장 나쁘다. 로그아웃은 클라이언트가 저장된 토큰을 지우는 것이고, 그 사실이 코드에서 눈에 보이는 편이 정직하다 |
| **나중에** | 서버 무효화가 필요해지면 토큰에 `jti`(토큰 고유 id)를 넣고 폐기 목록을 두는 **별건 작업**이다 |

### 9-5. `TEST_MODE` 테스트유저 전환 장치를 없애지 않고 병존시켰다

| | 내용 |
|---|---|
| **갈림길** | A. `TEST_MODE` 경로 병존 / B. 테스트유저 장치 전부 제거 / C. `test_user` 데이터를 첫 카카오 계정으로 이관 |
| **택한 것** | **A. 병존** (리더 권장안으로 확정, 사용자에게 재질문하지 않음) |
| **왜 다른 쪽을 버렸나** | B는 진실의 출처가 하나로 정리돼 가장 깨끗하다. 그런데 **테스트유저 전환 드롭다운은 편의 기능이 아니라 "다인원 시나리오 QA의 유일한 진입점"이다** — 기능 6(현장 N명)과 기능 8(남의 질문 알림)은 **서로 다른 사용자 둘 이상**이 있어야 검증되고, 013·014·015의 QA가 전부 이걸로 돌았다. 없애면 카카오 실계정을 2개 이상 준비해야 QA가 가능하고, **출품 시연 직전에 검증 수단을 없애는 것은 위험하다.** C는 9개 테이블을 건드리는 일회성 스크립트라 되돌리기가 어렵고 "누가 첫 계정인가"의 판정이 자의적이다 |
| **대신 한 것** | 인증 경로가 2개가 되므로 **우선순위를 "실제 토큰 > 테스트 헤더"로 확정**하고 `deps.py` docstring에 그 이유를 길게 남겼다. 정리는 출품 이후 별건 |

### 9-6. 비로그인 쓰기를 전면 차단하되 버튼은 숨기지 않았다

| | 내용 |
|---|---|
| **갈림길** | A. `function.md` 표 그대로 최소 게이팅(`verify-location`·북마크는 비로그인 허용) / B. 쓰기 전면 로그인 / C. B + 버튼은 눌리게 두고 유도 시트 |
| **택한 것** | **C** (Q5, 사용자 확정) |
| **왜 다른 쪽을 버렸나** | A는 진입장벽이 가장 낮지만 **구조적으로 비싸다** — `presences`·`bookmarks`가 `users.id`에 외래키를 걸고 있어 **익명 행을 만들 수 없다.** 익명 사용자 테이블이나 nullable FK가 새로 필요해지고, "익명 사용자"라는 **두 번째 사용자 개념**이 생긴다. C는 FK 구조를 그대로 유지해 스키마 변경이 없고, "쓰기 = 로그인"이 예외 없는 한 문장이 되어 구현자·QA가 헷갈리지 않는다. 버튼을 숨기는 것(B)보다 눌리게 두는 것(C)이 나은 이유는 **숨기면 사용자가 기능의 존재 자체를 모르기 때문**이다 — `function.md:87`의 "진입장벽" 절충 의도에 C가 가장 부합한다 |
| **대가** | 기능 6의 "현장 N명"이 **로그인 사용자만 센다**는 뜻이 된다. 이건 013이 이미 인정한 과소집계 한계(웹은 탭을 닫으면 끊긴다)의 연장이고, 오히려 정의가 명확해진다 |

### 9-7. 카카오 JS SDK 팝업(Q1-B)을 택했다

| | 내용 |
|---|---|
| **갈림길** | A. 서버 주도 OAuth 전체 리다이렉트 / B. 카카오 JS SDK 팝업 / C. `kakao_flutter_sdk` Dart 패키지 |
| **택한 것** | **B** (사용자 확정) |
| **왜 다른 쪽을 버렸나** | A는 웹 표준이고 Client Secret이 서버에만 있어 가장 안전하지만, **전체 페이지 이동이라 Flutter 웹앱이 리로드된다.** 이 앱에서 그게 특히 비싸다 — **GPS 권한과 위치 획득이 제보·답변의 전제**인데(기능 3), 리로드하면 다시 받아야 한다. 현재 탭·스크롤도 초기화된다. C는 타입 안전하지만 **의존성이 하나 늘고**, 이 프로젝트는 지금까지 웹 연동을 전부 `index.html` + JS로 처리해 왔다(MapTiler). 패키지의 웹 지원은 네이티브만큼 사례가 두텁지 않고 `pubspec.lock` 변동이 Docker 빌드에 영향을 준다 |
| **B를 안전하게 만든 것** | JavaScript 키가 클라이언트에 노출되지만 **카카오 설계상 정상이며 도메인 등록으로 보호한다.** 그리고 P6대로 **서버가 반드시 카카오에 검증**하므로 JS 키 노출이 인증 강도를 낮추지 않는다 |
| **남은 위험** | 모바일 브라우저(특히 iOS Safari·인앱 브라우저)에서 팝업이 차단될 수 있다. 차단 시 카카오 `fail` 콜백 문구가 시트에 그대로 뜨므로 원인은 드러나지만, **A 경로로의 폴백은 없다**(11절) |

### 9-8. `users.firebase_uid` 컬럼을 이번에 정리했다

| | 내용 |
|---|---|
| **갈림길** | 컬럼 이름을 그대로 두고 값만 카카오 회원번호로 쓸 것인가, rename할 것인가 |
| **택한 것** | **`auth_provider`(String(20)) + `provider_user_id`(String(128)) 로 분리 rename** |
| **왜 다른 쪽을 버렸나** | Firebase를 안 쓰기로 한 이상 `firebase_uid`라는 컬럼명은 **거짓말이 된다.** 015 일지 469행이 "로그인 붙일 때 스키마 한 번 정리"를 이 시점에 명시적으로 예약해 뒀다. 이름이 틀린 컬럼은 다음 사람이 매번 코드를 읽어야 의미를 알 수 있다 |
| **불필요한 복잡도를 피한 것** | unique 제약을 **(provider, id) 복합으로 만들지 않았다.** 이름 없는 UNIQUE 제약을 떼어내는 방식이 SQLite batch 모드와 PostgreSQL에서 서로 달라 위험한 데 비해, provider가 하나뿐인 지금(P1: 카카오만) 복합으로 얻는 것이 없다. 두 번째 provider가 생기면 그때 옮긴다 |
| **주의했던 것** | `dev.py`가 `firebase_uid.like("seed_user_%")`로 **테스트유저를 판별하는 데 이 컬럼을 쓰고 있었다.** 함께 안 고쳤으면 테스트유저 전환 기능이 조용히 깨졌을 것이다. `seed.py`·`scripts/seed_dev_data.py`도 같은 이유로 함께 고쳤다(8-5 참고) |

### 9-9. WebSocket 토큰을 쿼리 파라미터로 보내는 것을 감수했다

| | 내용 |
|---|---|
| **갈림길** | 브라우저 WebSocket API는 **커스텀 헤더를 실을 수 없다**(P14). 그래서 `Authorization` 헤더를 못 쓴다. 대안은 셋 — 쿼리 파라미터 / `Sec-WebSocket-Protocol` / 연결 후 첫 메시지로 전송 |
| **택한 것** | **쿼리 파라미터 `?token=<JWT>`** |
| **왜 다른 쪽을 버렸나** | 나머지 두 방식은 클라이언트 구현이 눈에 띄게 복잡해진다. 반면 **이 채널은 알림 데이터를 실어 나르지 않고 "뭔가 왔다"는 빈 신호만 보내며**, 폴링이라는 동등한 폴백이 이미 있어 노출 가치가 낮다 |
| **대가 (숨기지 않는다)** | **토큰이 서버 액세스 로그에 URL로 남는다.** 로그를 볼 수 있는 사람은 그 토큰으로 해당 사용자 행세를 할 수 있다. **로그 보존 정책으로 다뤄야 할 항목**이다. 참고로 이번 교체 전에는 `?test_user_id=<uuid>`가 같은 자리에 남고 있었고, 014 일지가 "로그인이 붙으면 토큰 기반으로 교체해야 한다"고 예약해 둔 항목이었다 — 문제의 성격은 같고 값만 바뀌었다 |

### 9-10. `POST /api/dev/login-as/{user_id}`를 만든 이유

| | 내용 |
|---|---|
| **문제 상황** | `POST /api/auth/kakao`는 **유효한 카카오 토큰이 있어야** 토큰을 준다. 그런데 사용자가 카카오 키를 발급받는 중이라 그걸 구할 수 없었다. 그러면 인증 계층 자체(401 경계·WS 토큰·앱의 토큰 저장/복원)를 검증할 수단이 없다 — **로그인 이후의 모든 것이 검증 불가 상태로 남는다** |
| **택한 것** | 카카오 없이 **진짜 JWT**를 발급하는 개발 전용 엔드포인트. `/auth/kakao`와 **완전히 같은 응답 모양·같은 서명·같은 수명** |
| **안전장치 둘** | ⓐ `TEST_MODE=false`면 404 ⓑ **`auth_provider='test'`인 사용자에게만 발급** — 카카오 사용자 id를 넣으면 404. ⓑ가 없으면 `TEST_MODE`가 실수로 켜진 순간 **남의 실계정 토큰을 찍어내는 문**이 된다 |
| **결과** | 이것 덕분에 카카오 키 없이도 로그인 이후 화면 전체(프로필 카드·로그아웃·게이트 해제·스탯 조회·WS `?token=` 연결·새로고침 후 로그인 유지)를 개발하고 QA할 수 있었다. QA 실측에서 이 토큰으로 보호 엔드포인트 6종이 전부 200이었다 — **개발용 경로로 발급한 토큰이 실제 인증으로 완전히 동작한다** |

### 9-11. 상태관리를 Riverpod이 아니라 싱글턴 + ChangeNotifier로 했다

| | 내용 |
|---|---|
| **갈림길** | 기존 `providers/auth_provider.dart`(Riverpod `StateProvider<bool>`)를 살릴 것인가 |
| **택한 것** | **삭제하고 `AuthService` 싱글턴 + `ChangeNotifier`로 통일** |
| **왜 다른 쪽을 버렸나** | ⓐ `authStateProvider`가 단순 `bool`이라 **실제 로그인 상태(user_id·닉네임·토큰)를 담을 수 없었다.** ⓑ 그 파일은 `auth_service.dart`를 import하는데, 그 `auth_service.dart`가 **`pubspec.yaml`에 없는 `package:firebase_auth`를 import하고 있었다** — `dart analyze`에 error 1건을 남긴 채였고, **두 파일을 import하는 곳이 0개**라 지금까지 드러나지 않았다. ⓒ 이 프로젝트의 상태관리 다수파는 싱글턴 + ChangeNotifier다(`NotificationService`가 그렇다). 새 패턴을 만들지 않는다 |
| **013의 교훈과 같은 계열** | "죽은 경로를 밟고서야 드러나는 버그" — 로그인 작업은 정확히 그 경로를 밟는 작업이었다 |

---

## 10. 배운 것

1. **JWT는 암호화가 아니라 서명이다.** 내용물은 누구나 읽을 수 있고(Base64), 위조만 막는다. 그래서 **비밀번호나 민감정보를 토큰에 담으면 안 되고**, 우리는 내부 UUID만 담았다(카카오 회원번호도 안 담는다 — P4).

2. **`algorithms`를 명시하지 않은 JWT 검증은 뚫린다.** 생략하면 토큰 헤더의 `alg`를 그대로 믿게 되어 `alg: none`(서명 없음) 공격이 열린다. 라이브러리가 알아서 해 줄 것 같지만 아니다.

3. **"토큰이 유효한가"와 "우리 앱의 토큰인가"는 다른 질문이다.** 카카오 `/v2/user/me`는 앞의 것만 검사한다. 이 차이를 모르면 다른 앱에서 발급된 토큰으로 우리 서비스에 로그인할 수 있는 구멍이 생긴다.

4. **외부 API 실패 정책은 읽기와 인증이 정반대다.** 읽기(날씨·브리핑)는 실패해도 폴백 값을 보여 주는 게 맞지만, 인증에서 "확인 못 했으니 일단 통과"는 곧 아무나 남의 계정으로 들어오는 문이다.

5. **인증 실패 코드를 뭉개면 사용자가 할 수 있는 게 없어진다.** 401(다시 로그인하면 됨)과 502(네트워크 문제, 기다려야 함)를 같은 화면으로 처리하면 사용자가 로그인 버튼을 계속 누르는데 영원히 안 된다.

6. **호출부가 단일 지점으로 모여 있으면 대공사가 소공사가 된다.** 백엔드 27곳이 `Depends(get_current_user_id)` 하나만 보고 있었고, 프론트 40여 개 API 호출이 인터셉터 하나를 거치고 있었다. 그래서 "프로젝트 최초의 인증 계층 도입"이 실제로는 **양쪽 각 한 곳의 본문 교체**로 끝났다. 이건 운이 아니라 013·014에서 쌓인 설계 습관의 결과다.

7. **신원 체계가 하나에서 둘로 늘어나는 것은 겉보기보다 훨씬 넓게 번진다.** QA 실패 4건 중 3건이 이 계열이었다. "누구인가"를 읽는 코드는 인증 파일에만 있지 않다 — 뱃지 저장 키, 알림 폴링 시작 조건, 개발용 헤더 복원, 게이트 판정에 전부 흩어져 있었다.

8. **`.env.example`을 고치는 것과 `.env`를 채우는 것은 다른 일이다.** 전자는 코드 작업이고 후자는 사람이 해야 하는 일이다. 둘을 같은 것으로 취급하면 "경고 로그만 남고 보안 검증은 꺼진 채" 계속 동작한다(F4).

9. **`function.md`(설계서)는 설계 시점 문서라 이미 여러 곳이 낡았다.** 이번에만 두 곳이 사실과 달랐다 — Firebase 다리(근거가 사라짐)와 "MyPage 로그아웃은 죽은 메뉴"(항목 자체가 없어서 신규 추가였다). "죽은 메뉴를 살리면 되겠지"라고 착각하고 시작하면 예상이 빗나간다.

---

## 11. 현재 한계

### 미검증 (확인하지 못했다 — 통과로 적지 않는다)

| # | 항목 | 왜 못 했나 / 어떻게 확인하나 |
|---|---|---|
| **R1** | **실제 브라우저에서 카카오 JS SDK 팝업 로그인 종단 테스트** | 이 세션에 브라우저 도구가 없어 **정적·네트워크 분석까지만** 했다. SDK 파일을 실제로 받아 `Kakao.Auth.login`이 존재하고 팝업으로 동작함은 확인했으나(8-6), 실제 팝업이 뜨는 것은 못 봤다. **사용자가 직접 해야 한다** — `04_qa_report.md` 5절에 절차가 있다:<br>`flutter run -d chrome --web-port=8080 --dart-define=KAKAO_JS_KEY=<따옴표 없는 키>`<br>마이 탭 → "카카오로 시작하기" → 팝업이 뜨면 성공. 콘솔에서 `typeof Kakao`(→`"object"`), `Kakao.isInitialized()`(→`true`), `typeof Kakao.Auth.login`(→`"function"`)을 확인하면 원인이 바로 갈린다 |
| 2 | **Railway(Postgres)에서 마이그레이션 `d3a91f7c2b58` 적용** | 로컬은 **SQLite로만 검증**했다. 배포 시 `alembic upgrade head` 결과를 반드시 확인할 것. 이 마이그레이션은 `batch_alter_table`로 컬럼 rename을 하는데, SQLite와 PostgreSQL의 동작 방식이 다르다 |
| 3 | **카카오 개발자 콘솔의 사이트 도메인 등록** | 사용자 진행 중. 로컬 `http://localhost:8080` + 배포 도메인 **2개**를 등록해야 한다. 미등록이면 팝업이 뜨긴 하는데 **카카오 오류 페이지**를 보여 준다 — 이 증상이 나오면 원인은 SDK가 아니라 도메인 등록이다 |
| 4 | `POST /api/auth/kakao`의 **성공 경로 실호출** | 유효한 카카오 access token이 없으면 200을 만들 수 없다. 카카오 호출부만 스텁하고 그 앞뒤(요청 파싱 → 검증 분기 → upsert → JWT 발급 → 응답 직렬화)는 전 구간 실제 코드로 검증했다. **실패 경로(401/502)는 실제 왕복으로 검증됨.** 남은 위험은 카카오 응답 JSON의 실제 모양뿐이며, 닉네임·이미지는 `kakao_account.profile`과 `properties` 양쪽을 다 보도록 열어 뒀다 |
| 5 | 모바일/iOS Safari **팝업 차단** | 브라우저 없이는 재현 불가. 차단되면 카카오 `fail` 문구가 시트에 뜨므로 원인은 드러나지만 **폴백 경로(Q1-A 서버 주도 리다이렉트)는 없다** |
| 6 | AC4의 **앱 쪽** 확인 (로그아웃 → 같은 카카오 계정 재로그인 → 크레딧 동일) | 서버 쪽은 검증됨. 앱 쪽은 카카오 키를 넣고 실제로 두 번 로그인해야 한다 |
| 7 | AC7의 **브라우저 네트워크 탭 실측** (로그아웃 후 폴링·WS 정지) | 코드 경로와 서버 전제는 확인. 네트워크 탭 관찰은 브라우저 필요 |

### 알려진 대가 (고칠 수 있지만 의도적으로 안 한 것)

| # | 항목 | 나중에 어디에 연결하나 |
|---|---|---|
| 1 | **로그아웃해도 서버가 토큰을 무효화하지 못한다** | 9-3·9-4의 알려진 대가. 필요해지면 토큰에 `jti`를 넣고 폐기 목록 테이블을 두는 **별건 작업**. 착수 지점은 `app/services/auth_token.py`의 `create_access_token`(jti 발급)과 `decode_access_token`(폐기 목록 조회) 두 함수 |
| 2 | **WS 토큰이 서버 액세스 로그에 남는다** | 9-9 참고. 코드로 고칠 수 있는 것이 없다(P14). **로그 보존 정책 항목**으로 다뤄야 한다 — Railway 로그 보존 기간 설정 시 이 사실을 근거로 쓸 것 |
| 3 | **`LogInterceptor`가 `Authorization` 헤더를 브라우저 콘솔에 매 요청 출력한다** | `api_service.dart`의 `requestHeader: true`. JWT가 콘솔 로그에 그대로 남는다. **이번에 손대지 않았다** — 기존 로깅 동작을 예고 없이 바꾸면 QA가 쓰던 로그가 사라진다. **운영 배포 전에 `kDebugMode` 가드를 붙일 것.** 붙일 자리는 `api_service.dart`의 `LogInterceptor` 생성 지점 한 곳 |
| 4 | **`KAKAO_APP_ID`가 비면 앱 소유 검증이 꺼진다** | 의도된 동작(키 없이 개발 가능). 현재 `.env`에는 채워져 있으나, **Railway 환경변수에도 반드시 설정해야 한다.** 안 하면 배포본에서 "다른 카카오 앱의 토큰으로 로그인 가능" 상태가 된다. 경고 로그가 계속 남으므로 배포 후 로그를 확인할 것 |
| 5 | **`JWT_SECRET`을 Railway에도 설정해야 한다** | 로컬 `.env`만 채웠다. Railway 환경변수가 비면 배포본은 개발용 기본값으로 동작한다 = **누구나 토큰 위조 가능**. 로컬과 다른 값을 써도 되지만(토큰이 갈릴 뿐), 반드시 임의의 긴 문자열이어야 한다 |
| 6 | **비로그인 사용자는 "현장 N명"에 집계되지 않는다** | 9-6의 알려진 대가. 기능 6의 과소집계 한계의 연장 |
| 7 | **`test_user`에 쌓인 기존 데이터의 귀속이 애매하다** | 9-5(병존)라 이번 범위 밖. 제보 51건·크레딧·북마크가 `test_user` 소유로 남아 있다. **출품 이후 별건** |
| 8 | **회원 탈퇴가 없다** | 9개 테이블이 `users.id`에 FK를 걸고 있어(reports·questions·answers·credit_ledger·bookmarks·presences·notifications·push_subscriptions·spot_notification_settings) 삭제 정책 설계가 별도 작업 분량이다. 로그인이 먼저 돌아야 논의가 가능하다 |
| 9 | **`dart:js`가 deprecated 상태** | `map_screen.dart`와 동일. `dart:js_interop`으로 옮기려면 **두 파일을 함께** 옮겨야 하는 별건. `dart analyze` info 2건 |
| 10 | **테스트유저 드롭다운과 실제 로그인의 병존** | 실제 로그인 중에는 드롭다운을 **비활성화**하고 이유를 문구로 띄운다(서버가 헤더를 무시하므로 전환해도 효과가 없다). 로그아웃하면 다시 쓸 수 있다 |

### 검증 통과 현황 (참고)

| 수용 기준 | 결과 |
|---|---|
| AC1 비로그인 읽기 200 | ✅ 실측 |
| AC2 비로그인 쓰기 401 (서버) | ✅ 실측 |
| AC2 비로그인 쓰기 게이트 (앱) | ✅ F1·F2 수정 후 |
| AC3 무효 자격증명 401 | ✅ 실측 (위조 서명·형식 오류·빈 값·없는 사용자 4종) |
| AC4 재로그인 시 user_id·크레딧 보존 | ✅ 서버 (카카오 호출부 스텁) / 앱 쪽 미검증 |
| AC5 응답 키 전부 snake_case | ✅ camelCase 0건 |
| AC6 `TEST_MODE=false`에서 헤더 무시 | ✅ 실측 (재기동 후 전수) |
| AC7 로그아웃 후 폴링·WS 정지, 배지 0 | ✅ 코드 경로 + 서버 전제 / 네트워크 탭 미검측 |
| `dart analyze` | ✅ 69건 = 착수 기준선 69건, 순증 0 |
| 마이그레이션 | ✅ SQLite (31행 백필, reports 51행 무손실) / ❌ Postgres 미검증 |

---

## 12. 다음 단계

### 바로 해야 하는 것 (사용자)

1. **R1 브라우저 확인** — `flutter run -d chrome --web-port=8080 --dart-define=KAKAO_JS_KEY=<따옴표 없는 32자 키>` 후 마이 탭에서 "카카오로 시작하기". ⚠️ `.env`의 `KAKAO_JS_KEY` 값이 따옴표로 감싸여 있으므로(실측: 34자 = 키 32자 + `"` 2개) **따옴표를 빼고 넘겨야 한다.** 따옴표째 넘기면 `Kakao.init()`이 잘못된 키로 초기화된다.
2. **카카오 개발자 콘솔에 사이트 도메인 2개 등록** — `http://localhost:8080` + 배포 도메인.
3. **Railway 환경변수에 `JWT_SECRET`·`KAKAO_APP_ID` 설정** + `TEST_MODE=false` 확인.
4. **배포 시 `alembic upgrade head` 결과 확인** (Postgres 마이그레이션, 11절 미검증 2).

### 이어지는 작업

| 작업 | 어디에 연결되나 |
|---|---|
| **운영 배포 전 `LogInterceptor` `kDebugMode` 가드** | `api_service.dart`의 `LogInterceptor` 생성 지점 한 곳. 11절 알려진 대가 3 |
| **회원 탈퇴** | 9개 FK 테이블의 삭제 정책(CASCADE / 익명화 / 보존) 설계가 선행돼야 한다. 로그인이 돌기 시작했으므로 이제 논의 가능 |
| **`test_user` 데이터 정리** | 출품 이후. `TEST_MODE` 장치 제거와 한 세트로 묶어서 하는 것이 맞다(9-5) |
| **토큰 무효화(`jti` + 폐기 목록)** | `auth_token.py`의 두 함수. 실사용자가 생기고 보안 요구가 올라가면 |
| **`dart:js` → `dart:js_interop` 이관** | `kakao_login_bridge.dart` + `map_screen.dart` 두 파일을 함께 |
| **모바일 팝업 차단 폴백(Q1-A 경로)** | R1 확인 시 iOS Safari에서 팝업이 막히는 것이 확인되면. 백엔드에 `kakao_authorization_code`를 받는 경로 추가 + `KAKAO_REST_API_KEY` + Redirect URI 등록이 필요하다 |
| **프로필 이미지 실제 표시 확인** | `profile_image_url`이 nullable이고 카카오 미동의 시 `null`이다. 실제 카카오 로그인 후 이미지가 뜨는지 확인 |

---

## 변경 이력

### 2026-09-14 — 최초 작성
- 기능 완료 시점 기록. QA 실패 4건(F1~F4) 전부 처리 완료 상태.
- 남은 것: R1 브라우저 종단 테스트, Railway Postgres 마이그레이션 적용, 카카오 사이트 도메인 등록 — 셋 다 사용자가 브라우저·배포 환경에서 직접 확인해야 하는 항목이다.

### 2026-09-14 — P22 부분 폐기 (후속 작업 017로 대체)

**이 일지 본문은 완료 시점 기록이라 그대로 둔다.** 다만 아래 두 가지는 **지금 코드와 다르다** — `docs/worklogs/017-app-owned-unique-nickname.md`가 이긴다.

| P22의 내용 | 현재 |
|---|---|
| 닉네임 출처 = **카카오** | **사용자가 앱에서 직접 입력** (017 P23). 카카오는 회원번호만 준다 |
| **중복 허용, unique 제약 없음** | **unique 제약 `uq_users_nickname`** (017 P24). 닉네임 미설정(`NULL`) 상태가 새로 생겼다 |

**P22에서 그대로 살아 있는 것**: "식별 키는 내부 UUID(`users.id`)뿐이고 닉네임을 식별/매칭 키로 쓰지 않는다." unique는 표시 계층의 제약이지 식별 체계의 변경이 아니다.

**함께 뒤집힌 것**: P10(카카오 프로필 이미지 수신·매 로그인 갱신) — 카카오 동의 항목을 **전부 해제**해 닉네임·프로필 사진을 아예 받지 않는다(017 P34~P41). `kakao_auth.py::fetch_profile()`은 `verify_and_get_kakao_id()`로 이름이 바뀌었고, `index.html`의 `scope` 키는 삭제됐다. `users.profile_image_url` 컬럼은 남아 있으나 **값은 항상 `NULL`**이다.

**해소된 한계**: 없음. R1(브라우저 종단 테스트)·Railway Postgres 마이그레이션은 **여전히 미검증**이고 017에도 U1·U2로 그대로 넘어갔다.
