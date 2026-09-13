"""질문/답변 알림(기능 8)의 대상 판정·생성·조회·전달을 한 곳에 모은 모듈.

왜 별도 모듈인가: 알림을 만드는 지점이 `api/questions.py`의 **두 곳**(질문 등록·답변 등록)이고
읽는 지점이 `api/notifications.py`다. 세 곳이 각자 만료를 계산하면 "알림은 갔는데 목록엔
없다" 같은 어긋남이 생긴다. `credit.py`·`report_window.py`를 따로 뺀 것과 같은 이유다.

핵심 규칙(01_spec.md 2절 + **0절 방향 수정 2026-09-10**):

**2026-09-13 정책 축소(015)** — 014에서 확정했던 2건이 사용자 지시로 뒤집혔고, 그중 한 건은
같은 날 다시 정정됐다:

- **알림 종류는 `NEW_QUESTION`·`NEW_ANSWER` 2종이다**(015 Q1=D, 2-2절 사용자 정정).
  한때 "인앱 알림은 답변만"으로 읽고 `NEW_QUESTION` 생성을 중단했지만, 사용자의 의도는
  **"알림 목록 *페이지*를 없애라"**였지 **"새 질문 도착 시 뜨는 실시간 모달을 없애라"**가
  아니었다. 이 프로젝트에서 모달·미읽음 배지·목록은 전부 `GET /api/notifications` 응답
  하나에서 갈라지므로, 생성을 끊자 모달까지 같이 죽었다. 그래서 **생성도 목록 포함도
  원상복구**했다 — `create_question`이 다시 `prepare_new_question()`을 부르고,
  `active_join()`의 타입 필터는 제거됐다. "목록 페이지가 없다"와 "목록 조회에 포함된다"는
  다른 층위다: 후자는 모달·배지가 쓰는 내부 데이터일 뿐이고, 그 목록을 사용자에게 보여주는
  화면(내 Q&A의 "알림" 탭)은 015에서 없앤 채로 둔다.
- **전역 알림 스위치(`user_notification_settings`)는 폐기됐다**(015 N1·N2·Q3=B). 토글 UI와
  `GET/POST /push-settings`, `get/set_push_enabled`, `_disabled_user_ids`가 전부 제거됐고
  테이블도 드롭 마이그레이션(`b7f3c1e9a204`)으로 사라진다. **이건 정정 대상이 아니다 —
  그대로 삭제된 채로 둔다.** 남은 수신자 필터는 본인 제외(P7) 하나뿐이다.

- **알림 유발 본인은 제외**(P7). 답변자는 자기가 단 답변으로 알림을 받지 않는다(애초에
  본인 질문에는 답변할 수 없어 걸릴 일이 없지만, 규칙은 이 모듈 한 곳에서 강제한다).
- **발송 제한 3종은 폐기된 상태 그대로다**(P26). 인원 상한·시간당 상한·6시간 중복 금지 없음.
- **알림의 수명은 알림 자신이 아니라 연결된 질문이 정한다**(P24). `NOTIFICATION_TTL_MINUTES`
  (30분)는 폐기됐고, 목록·미읽음 수·읽음 처리 전부 `active_join()`으로 질문의
  `created_at + QUESTION_TTL_HOURS(2)`를 본다. 읽음(`read_at`)은 여기와 무관하게 별도다.
- **큐도 워커도 없다**(P6). 알림 INSERT는 질문/답변 저장과 같은 트랜잭션이다. 대신
  알림 쪽 실패가 질문/답변 저장을 롤백시키면 안 되므로, 이 모듈의 prepare_*/deliver는
  예외를 삼키고 로깅만 한다.
- **판정 SELECT는 반드시 `db.add()` 전에** 부른다. 세션에 pending 객체가 있으면 SELECT가
  autoflush를 유발한다(credit.py의 `prepare_award`와 같은 제약). 그래서 이 모듈은
  "명단을 고르는 단계"(SELECT, add 전)와 "행을 만드는 단계"(순수 함수, flush 후)를
  `PendingNotifications`로 분리한 구조를 유지한다.

전달(NotificationSender)은 인터페이스 뒤에 둔다(P14). 이번 범위의 구현체는 인앱 폴링
하나이고 실제로 아무것도 밀어 보내지 않는다 — 행을 저장한 것 자체가 전달이다. 나중에
Web Push나 FCM을 붙일 때 구현체 파일 하나를 추가하면 되고, `api/questions.py`는 손대지 않는다.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import List, Optional, Sequence, Tuple

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.notification import (
    TYPE_NEW_ANSWER,
    TYPE_NEW_QUESTION,
    Notification,
)
from app.db.models.question import QUESTION_TTL_HOURS, Question
from app.services.presence import get_onsite_user_ids
from app.services.report_window import question_validity_cutoff_utc
from app.services.ws_manager import manager as ws_manager

logger = logging.getLogger(__name__)

# 알림 문구. function.md 5장의 `motivation_texts` 테이블(A/B 테스트용 마스터 데이터)은
# MVP 범위 밖이라, 문구는 여기 상수로 조립한다. 본문 앞에 관광지 이름을 넣지 않는 이유:
# 이름 조회는 TourAPI 호출이라 질문 등록 응답 시간에 그대로 얹힌다. 대신 목록 조회 시점에
# `resolve_spot_names()`로 붙여 `spot_name` 필드로 따로 내려준다.
_BODY_PREFIX = {
    TYPE_NEW_QUESTION: "새로운 질문이 도착했습니다",
    TYPE_NEW_ANSWER: "내 질문에 답변이 달렸어요",
}
# 발췌를 붙이지 않는 종류. NEW_QUESTION은 사용자가 준 예시 문구를 그대로 쓴다(P28) —
# 수신자는 그 질문을 올린 사람이 아니라 "지금 그 관광지에 있는 사람들"이라, 질문 본문
# 일부를 보여줘도 어느 것인지 구분할 필요가 없다. 반대로 NEW_ANSWER는 질문자가 자기 질문
# 여러 개 중 어느 것에 답변이 달렸는지를 발췌로 구분한다.
_NO_EXCERPT_TYPES = {TYPE_NEW_QUESTION}
_EXCERPT_MAX = 40


def _excerpt(text: str) -> str:
    """알림 본문에 넣을 발췌. 질문·답변 본문은 최대 200자라 그대로 넣으면 배너를 넘긴다."""
    cleaned = " ".join((text or "").split())
    if len(cleaned) <= _EXCERPT_MAX:
        return cleaned
    return cleaned[:_EXCERPT_MAX] + "…"


def compose_body(notification_type: str, source_text: str) -> str:
    """알림 본문 조립. 종류에 따라 형식이 둘로 갈린다.

    - `NEW_QUESTION` → **고정 문구 하나만**("새로운 질문이 도착했습니다", P28). 발췌를
      이어붙이지 않는다.
    - `NEW_ANSWER` → `"프리픽스 — 발췌"`. 질문자는 자기 질문 여러 개 중 어느 것에 답변이
      달렸는지를 발췌로 구분하기 때문이다.
    """
    prefix = _BODY_PREFIX.get(notification_type, "새 알림")
    if notification_type in _NO_EXCERPT_TYPES:
        return prefix
    excerpt = _excerpt(source_text)
    return f"{prefix} — {excerpt}" if excerpt else prefix


# ──────────────────── 전달 경로 (채널 중립 인터페이스) ────────────────────


class NotificationSender:
    """알림을 실제로 사용자에게 밀어 보내는 경로. 구현체 교체가 호출부를 건드리지 않게 한다(P14).

    `api/questions.py`가 아는 것은 이 인터페이스뿐이다. 나중에 Web Push(pywebpush + VAPID)나
    FCM을 붙일 때 `deliver`를 구현한 클래스를 하나 추가하고 `get_sender()`가 그것을 돌려주게
    하면 끝이고, 질문/답변 등록 코드는 그대로다.
    """

    async def deliver(self, db: AsyncSession, notifications: Sequence[Notification]) -> None:
        raise NotImplementedError


class InAppNotificationSender(NotificationSender):
    """이번 범위의 구현체. **알림 데이터 자체는 밀어 보내지 않는다** — notifications 테이블에
    행을 저장한 것이 곧 전달이고, `GET /api/notifications`가 유일한 조회 경로다(P-M과 같은
    이유로 판정 로직을 두 곳에 두지 않는다).

    2026-09-12부터 여기서 하는 일이 하나 늘었다: 수신자가 지금 WebSocket에 연결돼 있으면
    "새 알림이 있다"는 빈 신호를 보낸다(`ws_manager.notify`). 이건 푸시가 아니라 **폴링
    주기를 기다리지 않게 하는 알림-깨우기**일 뿐이다 — 신호를 받은 클라이언트는 여전히
    `GET /api/notifications`를 다시 불러 실제 내용을 확인한다. 연결이 없는 사용자(WS 미접속,
    또는 폴백 폴링만 도는 상태)에게는 아무 일도 일어나지 않고, 다음 폴링에서 그대로 확인된다
    — 그래서 이 신호가 실패하거나 아예 안 가도 기능이 깨지지 않는다.

    push_subscriptions 테이블은 실제 Web Push/FCM 구현체를 위해 스키마만 미리 잡아 뒀다(P18)
    — 지금도 아무도 읽거나 쓰지 않는다. WebSocket 신호는 그것과 별개다.
    """

    async def deliver(self, db: AsyncSession, notifications: Sequence[Notification]) -> None:
        if not notifications:
            return
        logger.info(
            "notification.deliver in-app: %d건 (type=%s)",
            len(notifications),
            notifications[0].type,
        )
        # 알림마다 개별 신호를 보내지 않고 수신자당 한 번만 깨운다 — 한 번에 여러 건이
        # 생겨도(예: 현장 사용자 여러 명에게 NEW_QUESTION) 클라이언트는 다시 조회하는 순간
        # 목록 전체를 받으므로 신호를 여러 번 보낼 이유가 없다.
        for user_id in {n.user_id for n in notifications}:
            await ws_manager.notify(user_id)


_sender: NotificationSender = InAppNotificationSender()


def get_sender() -> NotificationSender:
    return _sender


async def deliver(db: AsyncSession, notifications: Sequence[Notification]) -> None:
    """commit 이후에 부른다. 전달이 실패해도 이미 저장된 알림 행은 남아야 하므로 예외를 삼킨다."""
    if not notifications:
        return
    try:
        await get_sender().deliver(db, notifications)
    except Exception:  # noqa: BLE001 - 전달 실패가 질문/답변 저장을 되돌리면 안 된다(P6)
        logger.exception("notification.deliver 실패 (알림 행은 이미 저장됨)")


# ──────────────────── 대상 판정 + 발송 제한 ────────────────────


@dataclass
class PendingNotifications:
    """"누구에게 · 어떤 알림을 보낼지"까지 정해졌지만 아직 행을 만들지 않은 상태.

    2단계로 나눈 이유: 대상 판정은 SELECT라서 `db.add()` **전에** 해야 하는데(autoflush
    회피), 알림 행에 넣을 question_id는 그 뒤에 확정되는 경우가 있다. 그래서 판정 결과를
    이 객체로 들고 있다가 나중에 `build()`로 행을 찍어낸다.
    """

    notification_type: str
    spot_content_id: str
    body: str
    recipient_ids: List[str] = field(default_factory=list)

    def build(self, *, question_id: Optional[str]) -> List[Notification]:
        return [
            Notification(
                user_id=user_id,
                type=self.notification_type,
                spot_content_id=self.spot_content_id,
                question_id=question_id,
                body=self.body,
            )
            for user_id in self.recipient_ids
        ]


async def select_recipients(
    db: AsyncSession,
    *,
    notification_type: str,
    spot_content_id: str,
    candidate_user_ids: Sequence[str],
    actor_user_id: str,
) -> List[str]:
    """후보 명단에 정책 필터를 적용해 최종 수신자를 고른다.

    **남은 필터는 본인 제외(P7) 하나뿐이다.** 전역 스위치 OFF 제외(P19)는 2026-09-13
    정책 축소로 제거됐다 — 토글 UI와 `user_notification_settings` 테이블이 함께 사라져
    "명시적으로 끈 사용자"라는 상태 자체가 존재하지 않는다(015 N2·N4).

    발송 제한 3종(질문당 최대 10명 ⓐ / 1인 시간당 최대 2회 ⓑ / 같은 사용자·관광지·종류
    6시간 재발송 금지 ⓒ)은 2026-09-10 방향 수정으로 **전부 폐기됐다**(P26).

    이 함수는 더 이상 SELECT를 돌리지 않지만(순수 필터), `db`·`notification_type`·
    `spot_content_id`는 시그니처에 남긴다 — 종류별 정책이 다시 생기면 호출부를 안 건드리고
    여기만 고칠 수 있게 하기 위함이다. 호출자는 여전히 `db.add()` **전에** 부른다.
    """
    # 순서를 보존하면서 중복만 제거한다(dict는 삽입 순서를 유지한다).
    return [uid for uid in dict.fromkeys(candidate_user_ids) if uid != actor_user_id]


async def prepare_new_question(
    db: AsyncSession,
    *,
    spot_content_id: str,
    actor_user_id: str,
) -> PendingNotifications:
    """질문 등록 시 — 그 관광지의 현장 사용자 전원에게 보낼 알림을 준비한다.

    **대상 판정은 새로 짜지 않는다.** `services/presence.py::get_onsite_user_ids()`를 그대로
    호출한다 — LIVE 상태창의 `onsite_user_count`가 쓰는 것과 **같은 함수·같은 cutoff**여서,
    "화면에는 3명이라고 떠 있는데 알림은 1명에게만 갔다"가 구조적으로 생기지 않는다(013/014의
    명시적 규칙). 여기서 쿼리를 복붙하는 순간 그 보장이 깨진다.

    본문은 발췌 없이 고정 문구 "새로운 질문이 도착했습니다"다(P28) — 질문 본문을 인자로
    받지 않는 이유가 이것이다.

    **반드시 `db.add(question)` 전에 부른다.** 안에서 SELECT(presences)가 돌기 때문에,
    세션에 pending 객체가 있으면 autoflush가 끼어들어 아직 완성되지 않은 질문 행을 INSERT
    하려 든다. 반환된 `PendingNotifications`는 question.id가 확정된 뒤(`db.flush()`)에
    `build(question_id=...)`로 행을 찍어낸다.

    대상 판정이 실패해도 예외를 올리지 않는다 — 질문 등록 자체가 롤백되면 안 된다(P6/N12).
    """
    pending = PendingNotifications(
        notification_type=TYPE_NEW_QUESTION,
        spot_content_id=spot_content_id,
        body=compose_body(TYPE_NEW_QUESTION, ""),
    )
    try:
        onsite_user_ids = await get_onsite_user_ids(db, spot_content_id)
        pending.recipient_ids = await select_recipients(
            db,
            notification_type=TYPE_NEW_QUESTION,
            spot_content_id=spot_content_id,
            candidate_user_ids=onsite_user_ids,
            actor_user_id=actor_user_id,
        )
    except Exception:  # noqa: BLE001
        logger.exception("NEW_QUESTION 알림 대상 판정 실패 (질문 등록은 계속 진행)")
        pending.recipient_ids = []
    return pending


async def prepare_new_answer(
    db: AsyncSession,
    *,
    spot_content_id: str,
    question_owner_id: str,
    actor_user_id: str,
    answer_content: str,
) -> PendingNotifications:
    """답변 등록 시 — 질문자 1명에게 보낼 알림을 준비한다.

    수신자가 항상 한 명이고,
    발송 제한 3종이 폐기돼(P26) 남은 판정은 본인 제외 하나뿐이다. 한 질문에 답변이
    연달아 달리면 알림도 그만큼 생긴다 — 이건
    사용자가 직접 올린 질문에 대한 응답이라 억제할 이유가 없다는 것이 새 정책의 판단이다.
    본인 제외(P7)는 이미 `create_answer`가 "본인 질문에는 답변 불가"로 막고 있어 걸릴 일이
    없지만, 규칙을 이 모듈 한 곳에서 강제하려고 동일하게 통과시킨다.
    """
    pending = PendingNotifications(
        notification_type=TYPE_NEW_ANSWER,
        spot_content_id=spot_content_id,
        body=compose_body(TYPE_NEW_ANSWER, answer_content),
    )
    try:
        pending.recipient_ids = await select_recipients(
            db,
            notification_type=TYPE_NEW_ANSWER,
            spot_content_id=spot_content_id,
            candidate_user_ids=[question_owner_id],
            actor_user_id=actor_user_id,
        )
    except Exception:  # noqa: BLE001
        logger.exception("NEW_ANSWER 알림 대상 판정 실패 (답변 등록은 계속 진행)")
        pending.recipient_ids = []
    return pending


# ──────────────────── 조회 · 읽음 ────────────────────


def active_join(stmt):
    """앱에 보일 알림만 남기는 공통 조건.

    **종류 필터는 없다 — `NEW_QUESTION`·`NEW_ANSWER` 둘 다 통과한다.** 2026-09-13 오전에
    `type == 'NEW_ANSWER'` 필터를 한 번 걸었다가 같은 날 되돌린 자리다(015 2-2절). 그때
    배운 것: **이 함수가 실시간 모달의 데이터 소스이기도 하다.** 프론트
    (`notification_service.dart::_applyList`)는 `GET /api/notifications`가 돌려준 목록에서
    "새로 나타난 id"를 찾아 모달을 띄우므로, 여기서 타입을 걸러내면 목록·미읽음 배지만이
    아니라 **모달까지 조용히 사라진다.** "사용자에게 목록 페이지를 보여주지 않는다"는
    화면 층위의 결정이고, 이 함수는 그 아래 데이터 층위다 — 섞지 않는다.

    **만료 필터 — 연결된 질문이 아직 2시간 유효한가**(P24). 알림 자신의 나이는 보지
    않는다. 3일 전에 만든 알림이라도 질문이 방금 올라온 것이면 살아 있고, 30분 전 알림이라도
    질문이 2시간을 넘겼으면 사라진다.

    `Notification.question_id`에는 FK가 없다(모델 docstring 참조 — 알림은 "그때 이런 일이
    있었다"는 기록이라 원본 질문이 사라져도 남아야 한다). 그래서 **애플리케이션 레벨
    JOIN**을 명시적으로 건다. INNER JOIN이므로 question_id가 null이거나 질문 행이 이미
    사라진 알림은 목록에서 빠진다 — 두 종류 모두 question_id를 항상 채우므로 실제로
    걸리는 행은 없고, 걸린다면 그건 탭해도 갈 곳이 없는 알림이라 빠지는 게 맞다.

    **판정은 반드시 여기 한 곳에만 넣는다.** 목록(`list_active`)·미읽음 수(`count_unread`)·
    읽음 처리(`list_unread_for_update`) 세 곳이 이 함수를 공유하므로, 호출부마다 따로 넣으면
    "배지엔 3건인데 목록은 비어 있는" 상태가 정확히 그렇게 생긴다. 되돌릴 때도 마찬가지다 —
    2026-09-13의 필터 추가·제거 둘 다 이 한 줄만 고쳐서 세 곳에 동시에 반영됐다.
    """
    return stmt.join(Question, Question.id == Notification.question_id).where(
        Question.created_at >= question_validity_cutoff_utc(),
    )


async def list_active(
    db: AsyncSession, user_id: str, *, limit: int
) -> List[Tuple[Notification, datetime]]:
    """살아 있는 알림을 최신순으로. `(알림, 연결된 질문의 created_at)` 튜플을 돌려준다.

    질문의 created_at을 함께 돌려주는 이유: 라우터가 응답의 `expires_at`
    (= question.created_at + 2시간)을 계산해야 하는데, 알림 행마다 질문을 다시 조회하면
    N+1 쿼리가 된다. 어차피 만료 판정을 위해 JOIN을 걸고 있으므로 그 김에 같이 가져온다.
    """
    rows = await db.execute(
        active_join(select(Notification, Question.created_at))
        .where(Notification.user_id == user_id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
    )
    return [(row[0], row[1]) for row in rows.all()]


def expires_at_of(question_created_at: datetime) -> datetime:
    """알림이 목록에서 사라지는 시각. 질문의 유효시간 그 자체다(P24)."""
    return question_created_at + timedelta(hours=QUESTION_TTL_HOURS)


async def count_unread(db: AsyncSession, user_id: str) -> int:
    """미읽음 수. **목록과 같은 만료 기준**(active_join)을 쓴다."""
    count = await db.scalar(
        active_join(select(func.count(Notification.id))).where(
            Notification.user_id == user_id,
            Notification.read_at.is_(None),
        )
    )
    return int(count or 0)


async def list_unread_for_update(db: AsyncSession, user_id: str) -> List[Notification]:
    """읽음 일괄 처리 대상. 목록에 실제로 보이는(= 질문이 아직 유효한) 미읽음 알림만.

    이미 목록에서 사라진 알림에 read_at을 찍어봐야 보이는 변화가 없다.
    """
    rows = await db.execute(
        active_join(select(Notification)).where(
            Notification.user_id == user_id,
            Notification.read_at.is_(None),
        )
    )
    return [row[0] for row in rows.all()]
