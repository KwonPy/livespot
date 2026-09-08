from fastapi import APIRouter, HTTPException
from typing import List
from datetime import datetime
import uuid
from app.models.schemas import ReviewCreate, ReviewResponse
from app.services.tour_api import TourAPIService
from app.services.geo import calculate_distance_m

router = APIRouter()
tour_service = TourAPIService()

# Mock DB
_reviews_db = []

@router.post("", response_model=ReviewResponse)
async def create_review(review: ReviewCreate):
    # Verify GPS
    spot = await tour_service.get_spot_detail(review.spot_id)
    if not spot:
        raise HTTPException(status_code=404, detail="Spot not found")
        
    spot_lat = float(spot.get("mapy", 0))
    spot_lng = float(spot.get("mapx", 0))
    
    distance = calculate_distance_m(review.lat, review.lng, spot_lat, spot_lng)
    
    # 500 meters threshold for GPS verification
    is_verified = distance <= 500
    
    new_review = ReviewResponse(
        id=str(uuid.uuid4()),
        spot_id=review.spot_id,
        content=review.content,
        rating=review.rating,
        gps_verified=is_verified,
        created_at=datetime.now()
    )
    
    _reviews_db.append(new_review)
    return new_review

@router.get("", response_model=List[ReviewResponse])
async def get_reviews(spot_id: str):
    return [r for r in _reviews_db if r.spot_id == spot_id]
