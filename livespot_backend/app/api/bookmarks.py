"""북마크 (기능 12 MyPage).

설계 메모:
- 추가·해제 모두 **멱등**이다. 이미 북마크된 것을 다시 POST해도 409가 아니라 200이고,
  없는 것을 DELETE해도 404가 아니라 200이다. 상세페이지 버튼이 낙관적 토글이라
  중복 탭·재시도가 일상적으로 발생하는데, 거기에 에러 SnackBar가 뜨면 안 된다.
- GPS 현장 인증을 요구하지 않는다. 북마크는 "가고 싶다"의 표시이고 현장에 없는
  사람이 쓰는 기능이다(질문 작성과 같은 성격).
- Credit을 지급하지 않는다. 북마크는 남을 돕는 행동이 아니라 개인 편의 행동이다.
- 단건 상태 조회 엔드포인트는 두지 않는다. 목록 규모가 수십 건이라 상세페이지가
  `GET /api/bookmarks`를 받아 content_id 포함 여부로 판정하면 충분하다.
"""

from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_id
from app.db.models.bookmark import Bookmark
from app.db.session import get_db
from app.models.schemas import BookmarkCreate, BookmarkEntry, BookmarkToggleResponse
from app.services.spot_lookup import resolve_spot_cards

router = APIRouter()


@router.post("", response_model=BookmarkToggleResponse)
async def add_bookmark(
    payload: BookmarkCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """북마크 추가. 이미 있으면 그대로 두고 200을 돌려준다(멱등).

    존재 확인 후 INSERT 사이에 경쟁이 끼어들 수 있으므로 IntegrityError도 함께
    잡는다 — UNIQUE 제약이 최종 방어선이고, 조건문은 그 앞의 편의일 뿐이다.
    """
    existing = await db.execute(
        select(Bookmark).where(
            Bookmark.user_id == user_id,
            Bookmark.spot_content_id == payload.content_id,
        )
    )
    if existing.scalar_one_or_none() is None:
        db.add(Bookmark(user_id=user_id, spot_content_id=payload.content_id))
        try:
            await db.commit()
        except IntegrityError:
            await db.rollback()

    return BookmarkToggleResponse(content_id=payload.content_id, bookmarked=True)


@router.delete("/{content_id}", response_model=BookmarkToggleResponse)
async def remove_bookmark(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """북마크 해제. 없어도 200(멱등) — 해제의 목적은 "없는 상태"이고 그건 이미 달성됐다."""
    result = await db.execute(
        select(Bookmark).where(
            Bookmark.user_id == user_id,
            Bookmark.spot_content_id == content_id,
        )
    )
    bookmark = result.scalar_one_or_none()
    if bookmark is not None:
        await db.delete(bookmark)
        await db.commit()

    return BookmarkToggleResponse(content_id=content_id, bookmarked=False)


@router.get("", response_model=List[BookmarkEntry])
async def get_my_bookmarks(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """내 북마크 목록(최신순). 0건이면 빈 배열 — 빈 상태는 에러가 아니다.

    관광지 정보는 TourAPI에서 조인한다. 조회에 실패한 항목도 목록에서 빼지 않는다:
    spot_*가 null로 내려가고 앱이 폴백 문구를 그린다. 삭제된 관광지 하나 때문에
    사용자의 북마크가 화면에서 사라지면 "지운 적 없는데 없어졌다"가 된다.
    """
    result = await db.execute(
        select(Bookmark)
        .where(Bookmark.user_id == user_id)
        .order_by(Bookmark.created_at.desc())
    )
    bookmarks = result.scalars().all()
    cards = await resolve_spot_cards({b.spot_content_id for b in bookmarks})
    return [
        BookmarkEntry(
            content_id=b.spot_content_id,
            spot_name=cards.get(b.spot_content_id, {}).get("title"),
            spot_address=cards.get(b.spot_content_id, {}).get("address"),
            spot_image_url=cards.get(b.spot_content_id, {}).get("image_url"),
            created_at=b.created_at,
        )
        for b in bookmarks
    ]
