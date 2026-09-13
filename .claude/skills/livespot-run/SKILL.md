---
name: livespot-run
description: "LiveSpot 백엔드(FastAPI)와 Flutter 웹앱을 로컬에서 띄우고 스모크 검증한다. 서버 실행, uvicorn 기동, 포트 정리, curl로 API 응답 확인, flutter analyze, 앱 실행이 필요할 때 반드시 이 스킬을 사용할 것. '서버 띄워줘', '백엔드 실행', '앱 실행', 'curl로 API 응답 찍어보기', '동작 확인', '스모크 테스트', '포트가 이미 사용 중', '왜 화면이 안 바뀌지' 같은 요청에 모두 해당한다. Windows PowerShell 환경 전용 절차와 알려진 함정을 담고 있다."
---

# LiveSpot 로컬 실행 · 스모크 검증

Windows + PowerShell 환경 기준이다. 경로는 프로젝트 루트 `livespot/` 기준.

## 백엔드 (FastAPI, 포트 8000)

```
cd livespot_backend
./venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8000 --host 127.0.0.1
```

`venv`를 activate 하지 않고 **`./venv/Scripts/python.exe`를 직접 호출한다.** activate는 셸 상태를 바꾸는데 이 환경에서는 호출 간 셸 상태가 유지되지 않아 다음 명령에서 시스템 파이썬이 잡힌다.

`--reload`가 붙어 있으므로 백그라운드로 띄우고 살려둔다. 기동 확인:

```
curl -s -m 2 http://127.0.0.1:8000/health
# → {"status":"ok"}
```

`/health`가 응답하지 않으면 서버가 뜨지 않은 것이다. 로그를 읽고 원인을 특정하기 전에 curl을 반복하지 마라.

## Flutter 웹앱 (포트 8080)

```
cd livespot_app
flutter run -d chrome --web-port=8080
```

앱은 빌드가 느리고 포트·프로세스가 남기 쉬우므로 **자동 검증 흐름에서는 띄우지 않는다.** 앱 구동 확인은 사용자에게 맡기고, 자동 검증은 아래 `flutter analyze`까지만 한다.

```
cd livespot_app
dart analyze
```

**`flutter analyze` 대신 `dart analyze`를 쓴다.** 이 환경은 프로젝트 경로에 한글이 섞여 있어
`flutter analyze`가 analysis server 크래시(`FormatException: Unterminated string` → exit 255)로
항상 실패한다. `dart analyze`는 동일한 분석기를 쓰면서 정상 동작하므로 검증 결과는 같다.

경고를 포함해 0건이어야 통과다. 잔여 이슈가 있다면 **이번 작업이 추가한 건수가 0인지**를
착수 전/후 건수 비교로 확인하고, 기존 이슈는 별건으로 남긴다.

## 포트가 이미 사용 중일 때

```powershell
Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object OwningProcess
Get-Process -Id <PID>
Stop-Process -Id <PID> -Force
```

프로세스명이 `python`인지 확인한 뒤 종료한다. 무관한 프로세스를 죽이지 않기 위함이다.

### ⚠️ `--reload`로 띄운 uvicorn은 **자식 워커까지** 죽여야 한다

`uvicorn --reload`는 프로세스가 하나가 아니다. 포트를 잡고 있는 **부모(리로더)**가 `multiprocessing.spawn`으로 **자식 워커**를 띄우고, **실제로 요청을 처리하는 코드는 자식에 있다.** 그래서 `Get-NetTCPConnection`으로 찾은 PID만 죽이면 자식 워커가 **고아 프로세스로 살아남아 계속 예전 코드로 응답한다.** 증상은 "분명히 서버를 껐다 켰는데 코드 수정이 반영되지 않는다"이다 — 서버가 안 죽은 것이 아니라 **덜 죽은 것**이다.

```powershell
# 1) 포트를 잡고 있는 부모 PID
$parent = (Get-NetTCPConnection -LocalPort 8000 -State Listen).OwningProcess

# 2) 그 PID를 parent_pid= 로 갖는 자식 워커 찾기 (커맨드라인에 박혀 있다)
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*parent_pid=$parent*" } |
  Select-Object ProcessId, CommandLine

# 3) 자식 → 부모 순으로 종료
taskkill /PID <자식 PID> /F
taskkill /PID $parent /F

# 4) 정말 죽었는지 확인 — 아무것도 안 나와야 한다
Get-NetTCPConnection -LocalPort 8000 -State Listen
```

재시작 후에는 반드시 **바뀐 코드가 실제로 응답에 나타나는지**(새 엔드포인트 curl, 로그의 기동 시각 등)로 확인한다. `/health`만으로는 부모·자식 중 누가 답하고 있는지 구분되지 않는다.

## 스모크 검증 절차

새 엔드포인트나 스키마를 바꿨으면 **실제 응답 JSON을 반드시 눈으로 본다.** Pydantic 정의를 읽은 것은 검증이 아니다 — `response_model` 필터링·직렬화 설정 때문에 정의와 실제 응답이 다를 수 있다.

```bash
# 응답 전문
curl -s http://127.0.0.1:8000/api/live/hotspots

# 최상위 키만 뽑아 Dart fromJson과 대조 (배열 응답)
curl -s http://127.0.0.1:8000/api/live/hotspots | python -c "import sys,json; d=json.load(sys.stdin); print(sorted(d[0].keys()) if d else 'EMPTY')"

# 객체 응답
curl -s http://127.0.0.1:8000/api/live/status/126508 | python -c "import sys,json; print(sorted(json.load(sys.stdin).keys()))"
```

쓰기 엔드포인트는 실제로 한 건 등록해보고 결과를 확인한다. 읽기만으로는 GPS 검증·권한 분기가 검증되지 않는다.

```bash
curl -s -X POST http://127.0.0.1:8000/api/reports \
  -H "Content-Type: application/json" \
  -d '{"spot_content_id":"126508","crowdedness_level":"NORMAL","waiting_time":"NONE","content":"스모크","lat":37.5,"lng":127.0}'
```

좌표는 대상 관광지 반경 150m(= `GPS_VERIFICATION_RADIUS_M` 100 + `GPS_ERROR_MARGIN_M` 50) 안이어야 통과한다. 범위 밖 거부 응답도 함께 확인하면 검증이 완결된다.

## 알려진 함정

| 증상 | 실제 원인 | 확인 방법 |
|---|---|---|
| **코드를 고쳤는데 화면이 그대로** | 백엔드 스키마를 바꾼 뒤에는 앱 hot reload로 부족하다. 완전 재시작이 필요하다 | 코드 버그로 단정하기 전에 양쪽 다 재시작해보라. 실제로 이것 때문에 멀쩡한 코드를 뒤진 전례가 있다 |
| **목록이 비어 보임** | 백엔드는 정상인데 앱이 에러를 빈 상태로 뭉갠 것일 수 있다 | 먼저 curl로 서버 응답을 확인한다. 서버가 데이터를 주고 있으면 앱의 `FutureBuilder` 에러 분기를 의심하라 |
| **`null명 \| null건`으로 출력** | 서버 필드명과 Dart `json['키']` 불일치 | curl 응답 키 목록과 `fromJson`을 문자 단위로 대조 |
| **시각이 9시간 어긋남** | 서버는 naive UTC를 보내는데 Dart가 `Z`를 안 붙이고 파싱 | `HotspotEntry._parseUtc` 패턴 적용 여부 확인 |
| **`flutter analyze`가 `FormatException`/exit 255로 죽는다** | 프로젝트 경로에 한글이 섞여 있으면 analysis server가 크래시한다. 코드 문제가 아니다 | `dart analyze`로 대체 실행 (같은 분석기, 정상 동작) |
| **404** | 새 라우터를 `app/api/router.py`에 `include_router`로 등록하지 않음 | `router.py` 확인 |
| **외부 API 응답 없음** | TourAPI/Gemini 키 미설정 또는 일일 쿠터 소진 | `.env` 확인. 읽기 경로는 폴백으로 살아 있어야 정상이다 |

## 개발용 스위치 (`livespot_backend/.env`)

| 설정 | 용도 |
|---|---|
| `TEST_MODE=true` | `X-Test-User-Id` 헤더로 다른 테스트 유저 행세 가능. 여러 사용자의 제보 상황을 한 기기에서 재현할 때 |
| `DEMO_BYPASS_GPS=true` | GPS 범위 밖에서도 제보가 거부되지 않고 `gps_verified=false`로 저장. 유선/WiFi 노트북 시연용 |
| `SERVICE_AREA_FILTER=none` | 서울 외 지역도 노출 (개발용). 운영은 `seoul` |

둘 다 **실서비스 배포 시 반드시 끈다.** 켜져 있으면 누구나 헤더만으로 다른 사용자 행세를 할 수 있다.
