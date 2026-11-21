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
    price = price_service.get_current_price(db)
    last = db.query(models.PriceHistory).order_by(models.PriceHistory.id.desc()).first()
    return schemas.PriceOut(price=price, source="sina(Au99.99)", updated_at=last.created_at if last else None)


@router.get("/sources")
def all_sources():
    """多源报价交叉校验。"""
    return price_service.fetch_all_prices()


@router.get("/history", response_model=schemas.PriceHistoryOut)
def price_history(range: str = Query("1m", description="realtime/1m/3m/6m/1y"), db: Session = Depends(get_db)):
    from .. import models
    days_map = {"realtime": 1, "1m": 30, "3m": 90, "6m": 180, "1y": 365}
    days = days_map.get(range, 30)
    since = datetime.now() - timedelta(days=days)
    rows = db.query(models.PriceHistory).filter(
        models.PriceHistory.created_at >= since
    ).order_by(models.PriceHistory.created_at.asc()).all()
    points = [schemas.PricePoint(time=r.created_at, price=r.price) for r in rows]
    return schemas.PriceHistoryOut(range=range, points=points)
