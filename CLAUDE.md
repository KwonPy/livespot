# LiveSpot

AI 기반 실시간 여행 플랫폼. Flutter 웹앱(`livespot_app/`) + FastAPI 백엔드(`livespot_backend/`).

설계서는 `function.md`, **기능별 작업일지는 `docs/worklogs/NNN-기능명.md`**, 실행 명령은 `run.md`.

`function.md`는 설계 시점 문서라 이후 결정으로 여러 곳이 이미 덮여 있다. 정책이 충돌하면 **작업일지 9절(의사결정)이 이긴다** — 사용자가 준 정책 원문은 거기에만 남는다.

## 하네스: LiveSpot 풀스택 기능 개발

**목표:** 명세 판정 → 백엔드·프론트 병렬 구현 → 경계면 정합성 검증 → 작업일지까지 한 흐름으로 끝내고, 이 프로젝트에서 반복돼 온 백엔드↔프론트 경계면 버그를 구조적으로 막는다.

**트리거:**

| 요청 | 사용할 스킬 |
|---|---|
| 새 기능, 양쪽(백엔드+프론트)에 걸친 작업, 후속 재실행·수정 | `livespot-feature` (오케스트레이터) |
| 백엔드만 단발 수정 | `livespot-backend` |
| 프론트만 단발 수정 | `livespot-flutter` |
| 연동 확인, null·빈 화면 증상, 스키마 변경 후 점검 | `livespot-contract` |
| 서버·앱 실행, curl 스모크, 포트 정리 | `livespot-run` |
| 기능 완료 후 작업일지 작성 | `livespot-worklog` |

단순 질문(코드 위치 찾기, 개념 설명)은 스킬 없이 직접 응답한다.

**변경 이력:**

| 날짜 | 변경 내용 | 대상 | 사유 |
|---|---|---|---|
| 2026-09-01 | 초기 구성 (에이전트 5, 스킬 6) | 전체 | - |
| 2026-09-01 | 응답 필드 규약을 snake_case로 확정 | `livespot-backend`, `livespot-contract`, `spec-arbiter` | 코드 전체가 이미 snake_case. `function.md` 5장의 "camelCase 통일"은 폐기로 판정 |
| 2026-09-01 | `contract_diff.py` 번들링 | `livespot-contract/scripts/` | Pydantic↔Dart 키 대조가 매 검증마다 반복되는 작업이라 스크립트로 고정 |
| 2026-09-01 | 기록을 `task.md`/`decisions.md` 2개로 분리, 일지 형식 재설계 | `livespot-worklog`, `journal-keeper`, `spec-arbiter` | 기존 `task.md` 5섹션 형식은 사용자가 임의로 만든 것이라 폐기. 정책 원문은 참조 빈도가 달라 별도 파일로 분리하고, 교훈을 하네스 규칙으로 환원하는 "하네스 반영" 절을 신설 |
| 2026-09-01 | 위 분리를 되돌려 **기능별 단일 일지(`docs/worklogs/NNN-기능명.md`) 12절 형식**으로 통합. `decisions.md` 폐기(`docs/archive/`로 이동), `task.md` 폐기 | `livespot-worklog`, `journal-keeper`, `spec-arbiter`, `livespot-feature` | 사용자 지침. 일지의 독자는 1~2개월 뒤의 사용자 본인이고, 한 기능을 이해하려고 파일 2개를 오가는 구조가 복습에 불리하다. 정책 원문은 각 일지 9절(의사결정)에 인용 블록으로 보존 |
