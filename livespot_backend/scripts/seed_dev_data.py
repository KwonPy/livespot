"""개발용 목업 데이터 시드 스크립트.

test_user 30명 + 관광지별로 성격이 다른 제보 시나리오를 넣는다.
실사용자가 들어온 뒤에도 지우지 않고 개발/데모용으로 계속 남겨둘 데이터이므로,
firebase_uid를 "seed_user_"로 시작하게 해서 실제 로그인 사용자와 절대 겹치지 않게 하고,
몇 번을 다시 실행해도(재배포·재시딩) 행이 중복으로 쌓이지 않도록 멱등하게 만들었다.
제보(reports)는 LIVE 상태창(기능 5)이 "최근 N시간" 기준으로 판정하므로, 재실행할 때마다
client_request_id는 유지한 채 created_at을 "지금 기준 N분 전"으로 다시 맞춘다 — 그래야
데모를 언제 돌리든 시드 데이터가 항상 "방금 있었던 일"처럼 보인다.

실행:
    cd livespot_backend
    venv/Scripts/python.exe scripts/seed_dev_data.py
"""
import asyncio
import sys
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.config import settings  # noqa: E402
from app.db.session import AsyncSessionLocal  # noqa: E402
from app.db.models.user import User  # noqa: E402
from app.db.models.report import Report  # noqa: E402

SEED_USER_COUNT = 30
SEED_USER_PREFIX = "seed_user_"  # 실제 로그인 사용자(firebase_uid)와 절대 겹치지 않는 접두어
SEED_REQUEST_PREFIX = "seed_report_"

NOW = datetime.utcnow()


def user_id(i: int) -> str:
    return f"{SEED_USER_PREFIX}{i:02d}"


# ──────────────────── 시나리오별 관광지 (실제 TourAPI content_id) ────────────────────
# 주의: 예전에는 mock_data_service.dart의 하드코딩된(=실제와 무관한 임의) content_id를
# 그대로 가져다 썼다가, TourAPI에 물어보니 이름이 전혀 다르게 나오는 버그가 있었다
# (예: "126535"는 실제로는 롯데월드가 아니라 남산서울타워, "127538"은 DDP가 아니라
# 전북 진안의 하천이었다). LIVE 상태창·핫스팟 랭킹이 이제 이 content_id로 TourAPI를
# 실시간 조회해 제목을 붙이므로, 아래 4개는 GET /api/spots/{id}로 직접 확인한 값이다.
#
# SPOT_MANY_USERS_MIXED는 원래 경복궁(126508)이었다. 그런데 경복궁은 TourAPI 자신의
# 위치기반 검색(locationBasedList2)에서 반경 20km를 줘도 단 한 번도 나오지 않는다는 걸
# 직접 검증했다(같은 좌표의 부속 건물 "건청궁"은 6m 거리로 정상 노출됨 — areacode/
# sigungucode 필드가 TourAPI 쪽에서 비어 있는 게 원인으로 추정). 지도(위치기반 주변 조회)로
# 절대 뜨지 않는 곳을 "많은 사용자가 몰리는 대표 시나리오"로 쓰면 지도로 들어가서 확인하는
# 흐름 자체가 항상 깨지므로, 실제로 위치기반 검색에 뜨는 관광지로 교체했다.
SPOT_MANY_USERS_MIXED = "1849416"  # 대한민국역사박물관 — 여러 사용자 + 서로 다른 혼잡도, 전부 최근
SPOT_MANY_USERS_BUSY = "2476731"   # 롯데월드 아쿠아리움 — 여러 사용자, 다들 "혼잡"으로 일치, 최근
SPOT_NO_REPORTS = "2470006"        # 동대문디자인플라자(DDP) — 제보 0건 (의도적으로 아무것도 넣지 않음)
SPOT_STALE_ONLY = "126535"         # 남산서울타워 — 전부 2~10일 전 오래된 제보만 존재


def _report(*, user_idx: int, spot: str, crowd: str, wait: str, parking, comment, minutes_ago: float, seed_key: str) -> Report:
    return Report(
        user_id=user_id(user_idx),
        spot_content_id=spot,
        crowdedness_level=crowd,
        waiting_time=wait,
        parking_status=parking,
        comment=comment,
        gps_verified=True,
        client_request_id=f"{SEED_REQUEST_PREFIX}{seed_key}",
        created_at=NOW - timedelta(minutes=minutes_ago),
    )


def build_seed_reports() -> list[Report]:
    reports: list[Report] = []

    # ── 대한민국역사박물관: 8명이 서로 다른 혼잡도로 최근 5~90분 사이에 제보 (동일 장소·여러 사용자·혼잡도 혼재) ──
    mixed = [
        (1, "EASY", "NONE", "EASY", "한산해요", 5),
        (2, "EASY", "UNDER_10", None, None, 12),
        (3, "NORMAL", "UNDER_10", "NORMAL", "적당히 붐벼요", 20),
        (4, "NORMAL", "10_TO_30", "NORMAL", None, 33),
        (5, "BUSY", "10_TO_30", "FULL", "주차 자리가 없어요", 41),
        (6, "BUSY", "OVER_30", "FULL", "입장 대기줄 김", 58),
        (7, "NORMAL", "UNDER_10", None, "그럭저럭 다닐만함", 72),
        (8, "EASY", "NONE", "EASY", None, 88),
    ]
    for i, (uidx, crowd, wait, parking, comment, mins) in enumerate(mixed):
        reports.append(_report(
            user_idx=uidx, spot=SPOT_MANY_USERS_MIXED, crowd=crowd, wait=wait,
            parking=parking, comment=comment, minutes_ago=mins,
            # seed_key는 예전 경복궁 시절 이름을 그대로 씀 — client_request_id(행의 정체성)라
            # 바꾸면 새 행이 또 생기고 기존 8건은 경복궁에 남는다. seed_reports()의 upsert가
            # 이 키로 기존 행을 찾아 spot_content_id만 새 관광지로 옮겨 붙인다.
            seed_key=f"gyeongbokgung_{i}",
        ))

    # ── 롯데월드: 5명이 전부 "혼잡"으로 일치하는 최근 제보 (여러 사용자·같은 혼잡도) ──
    busy = [
        (9, "OVER_30", "FULL", "아틀란티스 대기 2시간", 3),
        (10, "OVER_30", "FULL", "사람 진짜 많아요", 9),
        (11, "10_TO_30", "FULL", None, 15),
        (12, "OVER_30", None, "매표소부터 줄 김", 22),
        (13, "10_TO_30", "FULL", "그래도 놀만함", 27),
    ]
    for i, (uidx, wait, parking, comment, mins) in enumerate(busy):
        reports.append(_report(
            user_idx=uidx, spot=SPOT_MANY_USERS_BUSY, crowd="BUSY", wait=wait,
            parking=parking, comment=comment, minutes_ago=mins,
            seed_key=f"lotteworld_{i}",
        ))

    # SPOT_NO_REPORTS(DDP)는 의도적으로 아무 행도 만들지 않는다 — "제보 없음" 화면 테스트용.

    # ── 남산서울타워: 전부 2~10일 전 — "오래된 제보만 존재" (LIVE 판정에서 제외되어야 하는 케이스) ──
    stale = [
        (14, "NORMAL", "UNDER_10", "NORMAL", "며칠 전 다녀왔어요", 2 * 24 * 60),
        (15, "BUSY", "OVER_30", "FULL", None, 5 * 24 * 60),
        (16, "EASY", "NONE", None, "주말인데도 한산했음", 10 * 24 * 60),
    ]
    for i, (uidx, crowd, wait, parking, comment, mins) in enumerate(stale):
        reports.append(_report(
            user_idx=uidx, spot=SPOT_STALE_ONLY, crowd=crowd, wait=wait,
            parking=parking, comment=comment, minutes_ago=mins,
            seed_key=f"namsan_{i}",
        ))

    return reports


async def seed_users(session) -> int:
    existing = set(
        (await session.scalars(
            select(User.firebase_uid).where(User.firebase_uid.like(f"{SEED_USER_PREFIX}%"))
        )).all()
    )
    created = 0
    for i in range(1, SEED_USER_COUNT + 1):
        uid = user_id(i)
        if uid in existing:
            continue
        session.add(User(
            id=uid,
            firebase_uid=uid,
            nickname=f"테스트유저{i:02d}",
        ))
        created += 1
    if created:
        await session.commit()
    return created


async def seed_reports(session) -> tuple[int, int]:
    """LIVE 상태창(기능 5)이 "최근 N시간" 기준으로 판정하므로, 시드 제보의 상대적 최신성이
    실제로 의미가 있으려면 재실행 시마다 created_at을 현재 시각 기준으로 다시 맞춰야 한다.
    client_request_id(정체성)는 그대로 두고 시간만 갱신하는 upsert 방식."""
    wanted = build_seed_reports()
    existing_rows = {
        r.client_request_id: r
        for r in (await session.scalars(
            select(Report).where(Report.client_request_id.like(f"{SEED_REQUEST_PREFIX}%"))
        )).all()
    }
    created = 0
    updated = 0
    for r in wanted:
        existing = existing_rows.get(r.client_request_id)
        if existing is None:
            session.add(r)
            created += 1
        else:
            existing.spot_content_id = r.spot_content_id
            existing.created_at = r.created_at
            existing.crowdedness_level = r.crowdedness_level
            existing.waiting_time = r.waiting_time
            existing.parking_status = r.parking_status
            existing.comment = r.comment
            updated += 1
    if created or updated:
        await session.commit()
    return created, updated


async def main():
    if "sqlite" not in settings.DATABASE_URL:
        print(f"DATABASE_URL이 SQLite가 아닙니다: {settings.DATABASE_URL}")
        print("배포/공유 DB에 테스트 데이터가 영구히 섞여 들어갈 수 있어 중단합니다.")
        print("정말 이 DB에 시드하려면 스크립트의 이 가드를 직접 지우고 실행하세요.")
        return

    async with AsyncSessionLocal() as session:
        user_created = await seed_users(session)
        report_created, report_updated = await seed_reports(session)

    print(f"users: {user_created}건 새로 생성 (총 {SEED_USER_COUNT}명 목표, seed_user_01~{SEED_USER_COUNT:02d})")
    print(f"reports: {report_created}건 새로 생성, {report_updated}건 시각 갱신")
    print("시나리오:")
    print(f"  - {SPOT_MANY_USERS_MIXED} (대한민국역사박물관): 8명, 최근 5~88분 전, 혼잡도 혼재")
    print(f"  - {SPOT_MANY_USERS_BUSY} (롯데월드 아쿠아리움): 5명, 최근 3~27분 전, 전부 BUSY")
    print(f"  - {SPOT_NO_REPORTS} (DDP): 제보 0건 (의도적)")
    print(f"  - {SPOT_STALE_ONLY} (남산서울타워): 3명, 2~10일 전 제보만 존재")
    print("다시 실행하면 seed_user_*는 그대로 재사용하고, seed_report_*는 시각/장소를 최신 값으로 갱신합니다.")


if __name__ == "__main__":
    asyncio.run(main())
