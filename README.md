# 🗺️ LiveSpot

> 여행지의 **'지금'**을 알려주는 AI 기반 실시간 여행 플랫폼

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![SQLAlchemy](https://img.shields.io/badge/SQLAlchemy_2.0-D71F00)](https://www.sqlalchemy.org)
[![TourAPI](https://img.shields.io/badge/한국관광공사_TourAPI-0B7285)](https://www.data.go.kr)

---

## 무엇을 하는 앱인가

관광지 정보는 공공데이터(한국관광공사 TourAPI)에서 실시간으로 가져오고, 그 위에 **GPS로 현장 인증된 사용자의 제보**를 얹어 "지금 그곳이 어떤지"를 보여준다.

**핵심 차별점 — 현장에 있는 사람만 쓸 수 있다.** 관광지 반경 150m 안에서만 제보·답변이 저장되고, 서버가 매 요청마다 좌표를 다시 계산해 판정한다.

---

## 주요 기능

| 기능 | 설명 | 상태 |
|---|---|---|
| 🗺️ **실시간 지도** | MapTiler 지도에 관광지 마커. 색상은 방문 집중률 예측 (🟢여유 / 🟡보통 / 🔴높음) | ✅ |
| 📍 **GPS 인증 제보** | 반경 150m 이내에서만 혼잡도·대기시간·주차 상황 제보 | ✅ |
| 🔴 **LIVE 상태창** | 최근 2시간 제보 건수 + 당일 현재 상황. 실시간 계산 | ✅ |
| 🔥 **핫스팟 랭킹** | 실제 제보가 있는 곳 우선, 부족하면 집중률 예측으로 채움 | ✅ |
| 💬 **현장 Q&A** | 멀리 있는 사람이 묻고, **현장 인증된 사람만** 답한다 (TTL 2시간) | ✅ |
| 🔔 **제보 유도 알림** | 알림 켠 관광지 50m 안에 들어오면 알림 (앱 실행 중일 때만) | ✅ |
| 🤖 **AI 브리핑** | Gemini 기반 현장 요약 | ⬜ 미연결 |
| 💎 **Credit 보상** | 제보 +30 / 답변 +50 | ⬜ |
| 🔐 **카카오 로그인** | 현재는 고정 `test_user`로 동작 | ⬜ |

---

## 기술 스택

| 영역 | 기술 |
|---|---|
| 프론트엔드 | Flutter 3.x (웹) + Riverpod + Dio |
| 백엔드 | Python FastAPI (async) |
| DB | SQLAlchemy 2.0 + Alembic — 로컬 SQLite, 배포 PostgreSQL |
| 지도 | MapTiler SDK JS (`web/index.html`에서 CDN 로드) |
| 공공데이터 | TourAPI(KorService2), 관광지 집중률(TatsCnctrRateService), 관광사진 갤러리 |
| AI · 날씨 | Google Gemini, OpenWeatherMap *(코드 존재, 미연결)* |
| 인증 | Firebase Auth + 카카오 *(예정)* |

---

## 프로젝트 구조

```
livespot/
├── livespot_app/              # Flutter 웹앱
│   └── lib/
│       ├── config/            # 테마, 상수, 라우트
│       ├── models/            # 서버 JSON → Dart 객체 (fromJson)
│       ├── services/          # api_service.dart 가 서버 호출 전담
│       ├── screens/           # 지도 · 라이브 · 상세 · 마이
│       └── widgets/           # 제보 모달, Q&A, 배지 등
│
├── livespot_backend/          # FastAPI
│   └── app/
│       ├── api/               # 라우터 (spots, reports, live, questions, notifications)
│       ├── db/models/         # SQLAlchemy 테이블
│       ├── models/schemas.py  # Pydantic 응답 스키마
│       └── services/          # TourAPI, 집중률, 지오, 캐시
│
├── docs/worklogs/             # 📓 기능별 작업일지 — 무엇을 왜 만들었는지
├── function.md                # 설계서 (전체 지도 + 미구현 기능 설계)
├── run.md                     # 실행 명령
└── CLAUDE.md                  # 개발 하네스 설정
```

---

## 시작하기

### 필요한 것
- Python 3.11+ / Flutter 3.x
- API 키: **TourAPI**(필수), MapTiler, OpenWeatherMap, Gemini (선택)

### 백엔드
```powershell
cd livespot_backend
.\venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --port 8000
```
→ API 문서: http://127.0.0.1:8000/docs

### 앱
```powershell
cd livespot_app
flutter run -d chrome --web-port=8080
```

### 데모용 시드 데이터
```powershell
cd livespot_backend
venv/Scripts/python.exe scripts/seed_dev_data.py
```
제보 시각을 실행 시점 기준으로 다시 맞춘다. **시연 직전에 한 번 실행할 것** — 안 그러면 제보가 "최근 2시간" 창 밖으로 밀려나 핫스팟이 빈다.

---

## ⚠️ 시연 전 확인

| 항목 | 내용 |
|---|---|
| **노트북에서는 제보가 안 된다** | 노트북은 GPS 칩이 없어 WiFi/IP로 위치를 추정한다. 오차가 100m~50km라 150m 판정을 통과할 수 없다. **휴대폰 브라우저로 접속**하거나 `.env`에 `DEMO_BYPASS_GPS=True`를 켠다 |
| `DEMO_BYPASS_GPS` | GPS 거리 판정 우회. 배포 시 **반드시 False** |
| `TEST_MODE` | 헤더로 작성자를 바꿀 수 있다. 배포 시 **반드시 False** — 켜져 있으면 누구나 다른 사용자 행세를 할 수 있다 |
| `SERVICE_AREA_FILTER` | 기본 `none`(전국). 운영 시 `seoul` |

---

## 문서

| 문서 | 내용 |
|---|---|
| [`docs/worklogs/`](docs/worklogs/) | **기능별 작업일지** — 무엇을 왜 만들었고 어떤 문제를 어떻게 풀었는지 |
| [`function.md`](function.md) | 설계서 — 전체 현황표, 남은 기능 설계, DB·API 목록 |
| [`run.md`](run.md) | 실행 명령 |

정책이 충돌하면 **작업일지 9절(의사결정)이 설계서보다 우선**한다.

---

*공모전 제출용 프로젝트입니다.*
