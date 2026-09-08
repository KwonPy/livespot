from datetime import datetime
from typing import Optional
from app.models.schemas import CrowdednessInfo
from app.services.congestion import CongestionService
import logging

logger = logging.getLogger(__name__)


class CrowdednessService:
    """혼잡도 서비스 - 실제 집중률 API + 시간 기반 fallback"""

    def __init__(self):
        self.congestion_service = CongestionService()

    async def estimate_crowdedness(
        self, spot_id: str, title: str = "", address: Optional[str] = None
    ) -> CrowdednessInfo:
        """
        관광지 혼잡도 추정
        1순위: TatsCnctrRateService 실제 데이터
        2순위: 시간 기반 휴리스틱 (fallback)

        ⚠️ 이 서비스는 기능 9 이전의 레거시다. 기능 9는 "예측(집중률)과 실측(현장 제보)을
        절대 하나로 합치지 않는다"는 원칙이라, 지도·상세페이지는 이 클래스를 쓰지 않고
        CongestionService를 직접 쓴다. 여기 남은 시간대 휴리스틱은 근거가 약한 추측값이라
        새로 쓰지 말 것 — 지금은 /crowdedness, /briefing 엔드포인트만 참조한다.
        """
        # 1. 실제 집중률 API 조회 시도
        try:
            congestion = await self.congestion_service.get_spot_congestion(
                spot_id, title, address
            )
            if congestion.level != "unknown":
                return CrowdednessInfo(
                    level=congestion.level,
                    description=congestion.description,
                )
        except Exception as e:
            logger.warning(f"집중률 API 조회 실패 (fallback 사용): {e}")

        # 2. Fallback: 시간 기반 휴리스틱
        now = datetime.now()
        hour = now.hour
        is_weekend = now.weekday() >= 5

        if 11 <= hour <= 15:
            level = "red" if is_weekend else "yellow"
            desc = "가장 붐비는 시간대입니다." if level == "red" else "사람이 제법 있습니다."
        elif 9 <= hour < 11 or 15 < hour <= 18:
            level = "yellow"
            desc = "사람이 적당히 있는 편입니다."
        else:
            level = "green"
            desc = "비교적 한산합니다."

        return CrowdednessInfo(level=level, description=desc)
