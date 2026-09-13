"""기능 8(질문/답변 알림) 실시간 전달을 위한 WebSocket 연결 관리자.

전달 수단이 "인앱"이라는 원칙(P18, `notification.py` 모듈 docstring)은 그대로다 — 이 모듈이
하는 일은 폴링을 없애는 게 아니라, 연결이 살아있는 동안 폴링 주기를 기다리지 않고 "새 알림이
있으니 지금 다시 읽어라"는 신호만 보내는 것이다. 실제 알림 데이터(무엇이 왔는지, 몇 건인지,
만료 여부)는 여전히 `GET /api/notifications` 하나만 계산한다 — `active_join()`이 목록·미읽음
수·읽음 처리 세 곳에서 이미 공유되는 것과 같은 이유로, 여기서도 판정 로직을 두 벌 만들지
않는다. 그래서 페이로드는 항상 내용 없는 신호(`{"type": "notification"}`) 하나뿐이다.

⚠️ **Railway 단일 인스턴스 배포를 전제로 한 설계다(2026-09-12, 사용자 확정).** 연결 목록을
프로세스 메모리에만 든다 — 인스턴스가 여러 개로 늘어나면 어떤 사용자가 어느 인스턴스에 붙어
있는지 서로 알 수 없어 알림이 조용히 전달되지 않는 인스턴스가 생긴다. 그때는 Redis pub/sub
등으로 교체해야 한다. 지금 규모(교내 프로젝트, 단일 dyno)에서는 그 비용을 들일 이유가 없다.
"""

import logging
from typing import Dict, Set

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class NotificationConnectionManager:
    """user_id -> 열린 WebSocket 연결들. 한 사용자가 탭을 여러 개 열 수 있어 집합으로 둔다."""

    def __init__(self) -> None:
        self._connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, user_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.setdefault(user_id, set()).add(websocket)

    def disconnect(self, user_id: str, websocket: WebSocket) -> None:
        conns = self._connections.get(user_id)
        if not conns:
            return
        conns.discard(websocket)
        if not conns:
            self._connections.pop(user_id, None)

    async def notify(self, user_id: str) -> None:
        """[user_id]에 열린 연결 전부에 신호를 보낸다. 이 사용자가 지금 접속해 있지 않으면
        (연결이 없으면) 아무 일도 하지 않는다 — 다음 폴링이나 재접속 시 목록으로 확인한다.

        한 연결이 끊겨 있어도(전송 실패) 나머지 연결·호출자에게 영향이 없어야 한다 —
        `notification.py::deliver()`가 이미 예외를 삼키지만, 여기서도 한 연결의 실패가
        같은 사용자의 다른 탭까지 막지 않도록 개별적으로 처리한다.
        """
        conns = self._connections.get(user_id)
        if not conns:
            return
        dead = []
        for ws in list(conns):
            try:
                await ws.send_json({"type": "notification"})
            except Exception:  # noqa: BLE001
                dead.append(ws)
        for ws in dead:
            conns.discard(ws)
        if not conns:
            self._connections.pop(user_id, None)

    def connected_user_count(self) -> int:
        """헬스체크/디버깅용. 응답 스키마에는 노출하지 않는다."""
        return len(self._connections)


manager = NotificationConnectionManager()
