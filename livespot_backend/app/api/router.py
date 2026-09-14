from fastapi import APIRouter
from app.api import spots, reviews, reports, notifications, dev, live, questions, credits, bookmarks, images, auth

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(spots.router, prefix="/spots", tags=["spots"])
api_router.include_router(reviews.router, prefix="/reviews", tags=["reviews"])
api_router.include_router(reports.router, prefix="/reports", tags=["reports"])
api_router.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
api_router.include_router(dev.router, prefix="/dev", tags=["dev"])
api_router.include_router(live.router, prefix="/live", tags=["live"])
api_router.include_router(questions.router, prefix="/questions", tags=["questions"])
api_router.include_router(credits.router, prefix="/credits", tags=["credits"])
api_router.include_router(bookmarks.router, prefix="/bookmarks", tags=["bookmarks"])
api_router.include_router(images.router, prefix="/images", tags=["images"])
