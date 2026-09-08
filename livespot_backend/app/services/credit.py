"""Credit 적립·집계·뱃지 판정을 한 곳에 모은 모듈 (기능 4 · 11).

왜 별도 모듈인가: 적립 트리거가 `api/reports.py`와 `api/questions.py` **두 곳**이고,
조회는 `api/credits.py`다. 세 파일이 각자 상한을 세거나 각자 등급 컷을 들고 있으면
"제보 화면에서는 적립됐다는데 마이 화면 숫자는 안 움직인다" 같은 어긋남이 생긴다.
`report_window.py`를 따로 뺀 것과 같은 이유다.

시간 규약: 원장의 created_at은 naive UTC. 일일 상한의 "하루"는 직접 계산하지 않고
`report_window.today_cutoff_utc()`(KST 자정)를 그대로 가져다 쓴다 — LIVE·브리핑·Q&A와
하루 경계가 갈리면 같은 사용자에게 서로 다른 "오늘"이 보인다.
"""

from typing import List, Optional, Sequence, Tuple

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.models.answer import Answer
from app.db.models.credit_ledger import CreditLedger
from app.db.models.question import Question
from app.db.models.report import Report
from app.db.models.user import User
from app.models.schemas import (
    ActivityCountResponse,
    CreditBadge,
    CreditLedgerEntry,
    CreditSummaryResponse,
)
from app.services.report_window import today_cutoff_utc

# 뱃지 등급표. (하한, code, label, emoji) — 하한 오름차순이어야 한다.
#
# 저장하지 않는 이유(function.md 기능 11): 등급은 누적 크레딧에서 항상 다시 계산할 수 있는
# 파생값이다. 컬럼에 박아두면 등급 컷을 조정할 때마다 전 사용자 행을 마이그레이션해야 하고,
# 그 사이 저장값과 실제 합계가 어긋나면 어느 쪽이 진실인지 알 수 없게 된다.
#
# 판정 기준은 **잔액이 아니라 누적**이다(P5). 나중에 크레딧 사용처가 생겨 잔액이 줄어도
# 등급은 내려가지 않는다 — "이만큼 기여했다"는 사실은 소비로 취소되지 않기 때문이다.
BADGE_TIERS: List[Tuple[int, str, str, str]] = [
    (0, "SPROUT", "새싹", "🌱"),
    (50, "VISITOR", "Spot 탐방객", "📍"),
    (100, "EXPLORER", "Spot 탐험가", "🧭"),
    (200, "VETERAN", "베테랑", "🏆"),
    (500, "MASTER", "마스터", "👑"),
]

REASON_REPORT = "REPORT"
REASON_ANSWER = "ANSWER"
SOURCE_REPORT = "report"
SOURCE_ANSWER = "answer"


def resolve_badge(total_earned: int) -> CreditBadge:
    """누적 크레딧으로 현재 뱃지와 "다음 등급까지 N점"을 계산한다.

    앱은 이 결과를 그리기만 한다 — 등급 컷 상수를 Dart에 복제하면 서버에서 컷을 바꿔도
    앱이 옛 기준으로 그리게 되고, 그 어긋남은 화면상 아무 에러도 내지 않아 발견이 늦다.
    """
    index = 0
    for i, (minimum, _code, _label, _emoji) in enumerate(BADGE_TIERS):
        if total_earned >= minimum:
            index = i
        else:
            break

    minimum, code, label, emoji = BADGE_TIERS[index]
    is_top = index == len(BADGE_TIERS) - 1

    if is_top:
        # 최상위 등급에서는 진행바를 그릴 대상이 없다. 0이나 자기 자신을 넣어 "다 채웠다"로
        # 보이게 하면 앱이 100% 진행바를 그려 오해를 준다 — 셋 다 명시적으로 null이다.
        return CreditBadge(
            code=code, label=label, emoji=emoji, min_credit=minimum,
            next_label=None, next_at=None, remaining=None,
        )

    next_min, _next_code, next_label, _next_emoji = BADGE_TIERS[index + 1]
    return CreditBadge(
        code=code,
        label=label,
        emoji=emoji,
        min_credit=minimum,
        next_label=next_label,
        next_at=next_min,
        remaining=max(0, next_min - total_earned),
    )


async def prepare_award(
    db: AsyncSession,
    user: User,
    *,
    amount: int,
    reason: str,
    source_type: str,
    source_id: str,
    spot_content_id: Optional[str],
    gps_verified: bool,
) -> Optional[CreditLedger]:
    """적립 자격을 판정하고, 자격이 있으면 원장 행 객체를 만들어 돌려준다.

    **세션에 add하지도 commit하지도 않는다.** 호출자가 기존 `await db.commit()` **앞**에서
    `db.add()` 해야 제보/답변 저장과 같은 트랜잭션에 묶인다. 여기서 따로 commit하면
    "제보는 저장됐는데 크레딧은 안 들어옴"(또는 그 반대)이 실제로 발생한다.

    자격이 없으면 None을 돌려주고, **호출자는 그래도 정상 200을 반환해야 한다**(P15).
    상한을 넘겼다고 제보 자체를 거부하면 사용자는 정보를 올릴 방법을 잃는다.

    주의: 이 함수는 SELECT를 수행하므로 호출 시점에 세션에 pending 객체가 있으면
    autoflush가 일어난다. 그래서 호출자는 `db.add(new_report)` **이전에** 부른다 —
    reports.py가 commit의 IntegrityError를 잡아 기존 행을 돌려주는 관례가 있는데,
    autoflush가 그 예외를 try 블록 밖에서 터뜨리면 그 관례가 깨진다.
    """
    if amount <= 0:
        return None

    # 크레딧의 명분은 "실제 현장에서 정보를 제공했다"이다. DEMO_BYPASS_GPS로 저장만 허용된
    # 원격 제보·답변(gps_verified=False)에까지 주면 그 정의가 무너진다.
    if not gps_verified:
        return None

    # 이미 지급된 건인가. 제보는 report.id가 매번 새로워 걸릴 일이 없고, 답변은
    # source_id가 question_id라 같은 질문에 두 번째 답변부터 여기서 걸러진다(P14).
    already = await db.scalar(
        select(CreditLedger.id).where(
            CreditLedger.user_id == user.id,
            CreditLedger.source_type == source_type,
            CreditLedger.source_id == source_id,
        )
    )
    if already is not None:
        return None

    # 같은 장소 하루 N건 상한. 여러 관광지를 도는 정상 사용자는 이 제한을 느끼지 않고,
    # 한 곳에서 제보를 반복해 무한 적립하는 경로만 막힌다.
    if spot_content_id:
        used = await db.scalar(
            select(func.count(CreditLedger.id)).where(
                CreditLedger.user_id == user.id,
                CreditLedger.spot_content_id == spot_content_id,
                CreditLedger.amount > 0,
                CreditLedger.created_at >= today_cutoff_utc(),
            )
        )
        if (used or 0) >= settings.CREDIT_DAILY_LIMIT_PER_SPOT:
            return None

    # 잔액 캐시 갱신도 같은 트랜잭션에 들어간다(P3). 원장과 캐시가 따로 commit되면
    # 둘이 어긋난 순간이 생긴다.
    user.credit_balance = (user.credit_balance or 0) + amount

    return CreditLedger(
        user_id=user.id,
        amount=amount,
        reason=reason,
        source_type=source_type,
        source_id=source_id,
        spot_content_id=spot_content_id,
    )


async def prepare_report_award(
    db: AsyncSession, user: User, *, report_id: str, spot_content_id: str, gps_verified: bool
) -> Optional[CreditLedger]:
    """제보 적립. source_id는 report.id — 제보 1건당 1회."""
    return await prepare_award(
        db, user,
        amount=settings.CREDIT_AMOUNT_REPORT,
        reason=REASON_REPORT,
        source_type=SOURCE_REPORT,
        source_id=report_id,
        spot_content_id=spot_content_id,
        gps_verified=gps_verified,
    )


async def prepare_answer_award(
    db: AsyncSession, user: User, *, question_id: str, spot_content_id: str, gps_verified: bool
) -> Optional[CreditLedger]:
    """답변 적립. source_id는 **answer.id가 아니라 question.id**다 — 한 질문에 여러 답변을
    다는 것은 허용이지만 적립은 질문당 1회다(P14).

    복수 답변이 정책상 허용인데 `create_answer`에는 제보의 client_request_id 같은 멱등
    장치가 없다. 막을 곳은 답변이 아니라 적립이고, source_id를 질문 단위로 잡으면
    UNIQUE(user_id, source_type, source_id) 제약 하나가 그대로 방어벽이 된다.
    """
    return await prepare_award(
        db, user,
        amount=settings.CREDIT_AMOUNT_ANSWER,
        reason=REASON_ANSWER,
        source_type=SOURCE_ANSWER,
        source_id=question_id,
        spot_content_id=spot_content_id,
        gps_verified=gps_verified,
    )


async def get_totals(db: AsyncSession, user_id: str) -> Tuple[int, int]:
    """(balance, total_earned). 둘 다 원장에서 계산한다.

    users.credit_balance라는 캐시 컬럼이 있지만 읽기는 원장을 본다. 이유: 캐시가 어긋난
    적이 있어도 화면에는 반드시 진실이 나와야 하고(P1: 진실은 원장 합계), 두 값이 한
    응답 안에 같이 나가므로 balance > total_earned 같은 모순이 절대 나오면 안 된다.
    캐시는 적립 시 계속 갱신하므로 다른 소비자(향후 차감 로직)는 그대로 쓸 수 있다.
    """
    balance = await db.scalar(
        select(func.coalesce(func.sum(CreditLedger.amount), 0)).where(CreditLedger.user_id == user_id)
    )
    earned = await db.scalar(
        select(func.coalesce(func.sum(CreditLedger.amount), 0)).where(
            CreditLedger.user_id == user_id, CreditLedger.amount > 0
        )
    )
    return int(balance or 0), int(earned or 0)


async def get_summary(db: AsyncSession, user_id: str) -> CreditSummaryResponse:
    """사용자도 원장도 없을 수 있다. 그때도 200 + 0 + 최하위 뱃지다(P23) —
    "아직 아무것도 안 했다"는 빈 상태이지 에러가 아니다."""
    user = await db.get(User, user_id)
    balance, earned = await get_totals(db, user_id)
    return CreditSummaryResponse(
        user_id=user_id,
        nickname=user.nickname if user is not None else "게스트",
        balance=balance,
        total_earned=earned,
        badge=resolve_badge(earned),
    )


async def get_ledger(db: AsyncSession, user_id: str, limit: int) -> Sequence[CreditLedgerEntry]:
    """최신순 원장 내역. 원장을 만든 이유가 "왜 줄었죠?"에 답하기 위함이므로,
    회수(음수) 행도 숨기지 않고 그대로 내려간다."""
    rows = await db.scalars(
        select(CreditLedger)
        .where(CreditLedger.user_id == user_id)
        .order_by(CreditLedger.created_at.desc(), CreditLedger.id.desc())
        .limit(limit)
    )
    return [CreditLedgerEntry.model_validate(row) for row in rows.all()]


async def get_activity(db: AsyncSession, user_id: str) -> ActivityCountResponse:
    """마이 화면 스탯 행의 실제 값.

    적립 여부와 무관한 **작성 총 건수**다. GPS 미인증이나 일일 상한 초과로 크레딧을 받지
    못한 글도 "내가 쓴 글"인 것은 사실이므로 센다. 그래서 report_count * 10 +
    answer_count * 5 가 total_earned와 일치하지 않을 수 있다 — 앱이 이 값으로 크레딧을
    역산하면 안 되는 이유이고, 크레딧은 /credits/me의 숫자를 그대로 쓴다.
    """
    report_count = await db.scalar(select(func.count(Report.id)).where(Report.user_id == user_id))
    answer_count = await db.scalar(select(func.count(Answer.id)).where(Answer.user_id == user_id))
    question_count = await db.scalar(select(func.count(Question.id)).where(Question.user_id == user_id))
    return ActivityCountResponse(
        report_count=int(report_count or 0),
        answer_count=int(answer_count or 0),
        question_count=int(question_count or 0),
    )
