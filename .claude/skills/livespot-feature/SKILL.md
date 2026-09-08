---
name: livespot-feature
description: "LiveSpot 기능 개발 에이전트 팀을 조율하는 오케스트레이터. 명세 판정 → 백엔드·프론트 병렬 구현 → 경계면 검증 → 작업일지까지 한 흐름으로 처리한다. '기능 N 구현해줘', '제보/Q&A/LIVE/혼잡도/브리핑/푸시/Credit/로그인 만들어줘', '화면과 API 같이 붙여줘', '이 기능 추가해줘', '풀스택으로 작업', '다음 단계 진행' 요청 시 반드시 이 스킬을 사용할 것. 후속 작업 — '다시 실행', '재실행', '수정해줘', '보완해줘', '업데이트', '이전 결과 기반으로', '백엔드만 다시', '프론트만 고쳐줘', 'QA만 다시 돌려줘', '지적된 것 반영' — 에도 반드시 이 스킬을 사용한다. 백엔드나 프론트 한쪽만 건드리는 단발 수정은 livespot-backend / livespot-flutter 스킬로 직접 처리하고, 양쪽에 걸치거나 새 기능이면 이 스킬을 쓴다."
---

# LiveSpot Feature Orchestrator

LiveSpot의 기능 하나를 명세 판정부터 작업일지까지 끝내는 통합 워크플로우.

## 실행 모드: 하이브리드

| Phase | 모드 | 이유 |
|---|---|---|
| 1 명세 판정 | 서브 에이전트 | 단독 읽기 분석. 팀 통신이 구조적으로 불필요 |
| 2 미결정 확인 | 리더 직접 | 서브 에이전트는 사용자에게 질문할 수 없다. 리더만 `AskUserQuestion`을 쓴다 |
| 3~4 구현 + 점진 QA | **에이전트 팀** | 응답 스키마 합의와 경계면 피드백이 실시간으로 오가야 한다. 이게 이 하네스의 핵심 |
| 5 작업일지 | 서브 에이전트 | 격리된 단발 작업 |

## 에이전트 구성

| 이름 | 타입 | Phase | 역할 | 스킬 | 출력 |
|---|---|---|---|---|---|
| `spec-arbiter` | 커스텀 | 1 | 문서·정책·코드 3자 대조, 미결정 추출 | (인라인) | `_workspace/01_spec.md` |
| `backend-builder` | 커스텀 | 3~4 | FastAPI·SQLAlchemy·Alembic | `livespot-backend`, `livespot-run` | `_workspace/02_backend_contract.md` |
| `flutter-builder` | 커스텀 | 3~4 | Dart 모델·ApiService·화면 | `livespot-flutter`, `livespot-run` | `_workspace/03_flutter_wiring.md` |
| `contract-qa` | 커스텀 | 3~4 | 경계면 교차 검증 + 실행 검증 | `livespot-contract`, `livespot-run` | `_workspace/04_qa_report.md` |
| `journal-keeper` | 커스텀 | 5 | 기능별 작업일지 | `livespot-worklog` | `docs/worklogs/NNN-기능명.md` (신규) |

모든 에이전트 호출에 `model: "opus"`를 명시한다.

---

## Phase 0: 컨텍스트 확인

`_workspace/`가 있는지 확인하고 실행 모드를 정한다.

| 상황 | 모드 | 행동 |
|---|---|---|
| `_workspace/` 없음 | **초기 실행** | Phase 1부터 |
| 있음 + 사용자가 부분 수정 요청 ("백엔드만 다시", "QA 지적 반영") | **부분 재실행** | 해당 에이전트만 재호출. 이전 산출물 경로를 프롬프트에 넣어 읽고 개선하게 한다. Phase 1·2는 건너뛴다 |
| 있음 + 새 기능 요청 | **새 실행** | `_workspace/`를 `_workspace_{YYYYMMDD_HHMMSS}/`로 이동한 뒤 Phase 1부터 |

부분 재실행이라도 **Phase 4(QA)는 반드시 다시 돈다.** 수정이 경계면을 깼는지는 재검증으로만 알 수 있다.

## Phase 1: 명세 판정

**실행 모드:** 서브 에이전트

```
Agent(
  subagent_type: "spec-arbiter",
  model: "opus",
  description: "명세 판정",
  prompt: "사용자 요청: {원문}
           docs/worklogs/의 관련 일지 9절(먼저), function.md, 관련 소스를 대조해 _workspace/01_spec.md를 작성하라.
           미결정 사항은 리더가 사용자에게 물을 수 있도록 선택지와 결과까지 적어라."
)
```

산출물이 없으면 다음 Phase로 넘어가지 않는다. 계약 없이 착수하면 재작업이 확정된다.

## Phase 2: 미결정 사항 확인 (리더가 직접)

`_workspace/01_spec.md`의 4절을 읽고, 각 미결정 항목을 `AskUserQuestion`으로 사용자에게 묻는다. 선택지와 각각의 결과를 그대로 옮긴다.

- 미결정이 0개면 이 Phase를 건너뛴다.
- 4개를 넘으면 **되돌리기 비싼 순서로 상위 4개만** 묻는다. 나머지는 권장안으로 진행하고 그 사실을 사용자에게 알린다.
- 확정된 답을 `_workspace/01_spec.md` 2절 "확정 정책"에 반영해 파일을 갱신한다. **이 파일이 이후 모두의 계약서이자 QA의 검증 기준이다.**

명세만으로 답이 정해지는 것은 묻지 않는다. 불필요한 질문은 사용자의 시간을 쓴다.

## Phase 3: 팀 구성

**실행 모드:** 에이전트 팀

```
TeamCreate(
  team_name: "livespot-feature-team",
  members: [
    { name: "backend-builder",  agent_type: "backend-builder",  model: "opus",
      prompt: "_workspace/01_spec.md를 계약서로 삼아 livespot_backend를 구현하라.
               스키마를 확정하는 즉시 flutter-builder에게 응답 shape 전문을 SendMessage로 보내라.
               엔드포인트가 하나 완성될 때마다 contract-qa에게 통지하라." },
    { name: "flutter-builder",  agent_type: "flutter-builder",  model: "opus",
      prompt: "_workspace/01_spec.md와 02_backend_contract.md를 근거로 livespot_app을 구현하라.
               계약이 아직 없으면 backend-builder에게 요청하고 그동안 계약 무관한 레이아웃을 진행하라.
               화면 하나 완성 시마다 contract-qa에게 통지하라." },
    { name: "contract-qa",      agent_type: "contract-qa",      model: "opus",
      prompt: "완성 통지를 받을 때마다 해당 경계면을 즉시 검증하라(점진 QA).
               발견은 파일:라인 + 수정 방법과 함께 담당자에게 SendMessage로 보내고,
               경계면 이슈는 양쪽 모두에게 알려라. 소스를 직접 고치지는 마라." }
  ]
)
```

작업 등록:

```
TaskCreate(tasks: [
  { title: "응답 스키마 확정 + 통지", assignee: "backend-builder" },
  { title: "DB 모델 + 마이그레이션",   assignee: "backend-builder" },
  { title: "라우터 구현 + router.py 등록", assignee: "backend-builder", depends_on: ["응답 스키마 확정 + 통지"] },
  { title: "백엔드 curl 스모크",       assignee: "backend-builder", depends_on: ["라우터 구현 + router.py 등록"] },
  { title: "Dart 모델 fromJson",       assignee: "flutter-builder", depends_on: ["응답 스키마 확정 + 통지"] },
  { title: "ApiService 메서드",        assignee: "flutter-builder", depends_on: ["Dart 모델 fromJson"] },
  { title: "화면·위젯 구현",           assignee: "flutter-builder", depends_on: ["ApiService 메서드"] },
  { title: "flutter analyze 0건",      assignee: "flutter-builder", depends_on: ["화면·위젯 구현"] },
  { title: "점진 경계면 검증",         assignee: "contract-qa" },
  { title: "실행 검증(uvicorn+curl+analyze)", assignee: "contract-qa", depends_on: ["백엔드 curl 스모크", "flutter analyze 0건"] },
  { title: "QA 리포트 작성",           assignee: "contract-qa", depends_on: ["실행 검증(uvicorn+curl+analyze)"] }
])
```

기능 규모가 작아 백엔드·프론트 중 한쪽만 변경된다면 해당 builder와 `contract-qa` 2명으로 팀을 줄인다. 쓸 일 없는 팀원은 조율 비용만 늘린다.

## Phase 4: 구현 + 점진 검증

**실행 모드:** 에이전트 팀 (팀원 자체 조율)

**통신 규칙:**
- `backend-builder` → `flutter-builder`: 스키마 확정 즉시 응답 shape 전문. 이후 필드 변경 시 즉시 재통지
- `flutter-builder` → `backend-builder`: 앱에 필요한데 응답에 없는 필드 요청 (앱에서 계산해 때우지 않는다)
- 양 builder → `contract-qa`: 모듈 완성 시마다 개별 통지 (전체 완료를 기다리지 않는다)
- `contract-qa` → 담당자: 파일:라인 + 수정 방법. 경계면 이슈는 양쪽 모두에게

**리더 모니터링:**
- 팀원 유휴 알림 수신 시 `TaskGet`으로 진행률 확인
- 막힌 팀원에게 `SendMessage`로 지시하거나 작업 재할당
- **`contract-qa`가 `04_qa_report.md`에 실패를 남긴 채 팀이 유휴가 되면 종료하지 않는다.** 담당 builder에게 수정을 지시하고 재검증을 요청한다
- 수정 ↔ 재검증 루프는 **최대 3회**. 3회 후에도 남으면 미해결로 기록하고 진행한다 (무한 루프 방지)

## Phase 5: 정리 + 작업일지

1. `TeamDelete`로 팀 정리 (서브 에이전트 호출 전에 반드시 먼저)
2. 작업일지:

```
Agent(
  subagent_type: "journal-keeper",
  model: "opus",
  description: "작업일지 기록",
  prompt: "_workspace/의 01~04 산출물과 아래 대화 맥락을 근거로 docs/worklogs/에 이번 기능의 작업일지를 새로 작성하라.
           쓰기 전에 ls docs/worklogs/로 기존 번호를 확인하고 다음 번호를 쓴다.
           사용자가 준 정책 원문은 9절에 원문 그대로 남겨라 — 다른 곳에 보관되지 않는다.
           사용자가 준 정책 원문: {인용}
           미해결로 남은 항목: {목록}"
)
```

3. `_workspace/`는 **보존한다** (사후 검증·감사 추적용). 삭제하지 않는다.
4. 사용자에게 보고: 구현된 것 / QA 통과·실패·미검증 / 미해결 항목 / **앱 구동 확인은 사용자가 직접 해야 한다는 안내**

## 데이터 흐름

```
사용자 요청
    ↓
[spec-arbiter] ──▶ 01_spec.md (미결정 목록)
    ↓
[리더 AskUserQuestion] ──▶ 01_spec.md 2절 갱신 (확정 정책 = 계약서)
    ↓
[팀] backend-builder ──SendMessage(응답 shape)──▶ flutter-builder
         │  02_backend_contract.md              │  03_flutter_wiring.md
         └──────────▶ contract-qa ◀─────────────┘
                          │ 04_qa_report.md
                          └─SendMessage(파일:라인+수정법)─▶ 담당 builder
    ↓
[journal-keeper] ──▶ docs/worklogs/NNN-기능명.md (12절: 왜·무엇·흐름·문제·의사결정·한계·다음)
```

## 에러 핸들링

| 상황 | 전략 |
|---|---|
| `spec-arbiter` 실패 | 1회 재시도. 재실패 시 리더가 직접 `function.md`·소스를 읽어 최소 계약을 세우고, 그 사실을 사용자에게 밝힌다 |
| 사용자가 미결정 답변을 보류 | 권장안으로 진행하되 `01_spec.md`에 "가정"으로 표기. 나중에 뒤집힐 수 있음을 보고에 명시 |
| 팀원 1명 실패/중지 | 리더가 `SendMessage`로 상태 확인 → 재시작. 재실패 시 남은 작업을 리더가 직접 수행 |
| 마이그레이션 실패 | 롤백. `livespot.db`를 삭제하지 않는다 (시드 데이터 소실) |
| QA 실패가 3회 루프 후에도 남음 | 미해결로 `04_qa_report.md`와 작업일지에 명시하고 진행. **통과로 뭉개지 않는다** |
| 외부 API 키 부재·쿼터 소진 | 읽기 경로는 폴백으로 살아 있어야 정상. QA는 "외부 의존 미검증"으로 기록 |
| 포트 8000 점유 | `livespot-run` 스킬의 포트 정리 절차. 프로세스명이 `python`인지 확인 후 종료 |
| 팀원 간 판단 충돌 | 삭제하지 않고 양쪽 근거를 병기해 리더가 판정. 규약(snake_case 등)이 있으면 규약이 이긴다 |

## 테스트 시나리오

### 정상 흐름 — "기능 6 현장 사용자 수 집계 구현해줘"
1. Phase 0: `_workspace/` 없음 → 초기 실행
2. Phase 1: `spec-arbiter`가 `function.md` 기능 6과 `presence` 테이블 설계를 대조 → `01_spec.md` + 미결정 2건("유지시간 10분 확정?", "위치 신호 전송 주기?")
3. Phase 2: 리더가 `AskUserQuestion` → 확정 → `01_spec.md` 2절 갱신 (이 확정 내용은 Phase 5에서 작업일지 9절로 넘어간다)
4. Phase 3: 팀 3명 + 작업 11개 등록
5. Phase 4: `backend-builder`가 `PresenceResponse` 확정 즉시 통지 → `flutter-builder` 병렬 착수 → `contract-qa`가 엔드포인트 완성마다 즉시 대조, `contract_diff.py` 실행, uvicorn+curl 확인
6. Phase 5: `TeamDelete` → `journal-keeper`가 `docs/worklogs/006-presence-count.md` 작성 (확정 정책 원문은 9절)
7. 예상 결과: `_workspace/01~04` 4개 파일, 백엔드·프론트 소스, `docs/worklogs/` 새 일지 1개

### 에러 흐름 — QA 실패가 반복될 때
1. Phase 4에서 `contract-qa`가 `MISSING: Dart가 json['user_nickname']을 읽지만 응답에 없음`을 발견
2. 규약상 앱이 계산하면 안 되는 값이므로 `backend-builder`에게 조인 필드 추가 요청 (양쪽 모두에게 통지)
3. 수정 후 재검증 → 이번엔 `NULLABLE` 발견 → `flutter-builder`가 `as String?`으로 수정
4. 3회차 재검증 통과 → Phase 5 진행
5. 3회를 넘겼다면 미해결로 `04_qa_report.md`·작업일지·사용자 보고에 모두 명시

### 부분 재실행 흐름 — "QA에서 지적된 것만 반영해줘"
1. Phase 0: `_workspace/` 존재 + 부분 수정 요청 → 부분 재실행. Phase 1·2 건너뜀
2. `04_qa_report.md`의 실패 항목을 읽어 담당 builder만 팀에 넣고 `contract-qa`와 2명으로 팀 구성
3. Phase 4 → Phase 5. `04_qa_report.md`는 덮어쓰지 않고 회차를 올려 추가
