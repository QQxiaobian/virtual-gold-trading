"""行情路由：当前金价、多源报价、历史走势。"""
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from .. import schemas, models
from ..database import get_db
from ..services import price_service

router = APIRouter(prefix="/api/market", tags=["行情"])


@router.get("/price", response_model=schemas.PriceOut)
def current_price(db: Session = Depends(get_db)):
    q = price_service.get_quote(db)
    return schemas.PriceOut(
        price=q["price"], buy_price=q["buy_price"], sell_price=q["sell_price"],
        spread=q["spread"], source=q["source"], updated_at=q["updated_at"],
    )


@router.get("/sources")
def all_sources():
    """多源报价交叉校验。"""
    return price_service.fetch_all_prices()


@router.get("/history", response_model=schemas.PriceHistoryOut)
def price_history(range: str = Query("1m", description="realtime/1m/3m/6m/1y/all"), db: Session = Depends(get_db)):
    days_map = {"realtime": 1, "1m": 30, "3m": 90, "6m": 180, "1y": 365, "all": 3650}
    days = days_map.get(range, 30)
    # 历史回填数据按"自然日"存储（created_at 为当日 00:00），实时数据为具体时刻。
    # 用 date 边界比较，避免当天 00:00 之后的历史点被 since 的时刻过滤掉。
    since_dt = datetime.now() - timedelta(days=days)
    rows = db.query(models.PriceHistory).filter(
        models.PriceHistory.created_at >= since_dt.replace(hour=0, minute=0, second=0, microsecond=0)
    ).order_by(models.PriceHistory.created_at.asc()).all()
    points = [schemas.PricePoint(time=r.created_at, price=r.price) for r in rows]
    return schemas.PriceHistoryOut(range=range, points=points)
