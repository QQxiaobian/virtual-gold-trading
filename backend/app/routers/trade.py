"""交易路由：账户总览、买入、卖出、充值、流水查询。"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from .. import models, schemas
from ..auth import get_current_user
from ..database import get_db
from ..services import trade_service, price_service

router = APIRouter(prefix="/api/trade", tags=["交易"])


@router.get("/portfolio", response_model=schemas.PortfolioOut)
def portfolio(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    price = price_service.get_current_price(db)
    return schemas.PortfolioOut(**trade_service.get_portfolio(db, current_user.id, price))


@router.get("/price")
def live_price(db: Session = Depends(get_db)):
    return {"price": price_service.get_current_price(db)}


@router.post("/buy", response_model=schemas.TransactionOut)
def buy(payload: schemas.TradeIn, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    try:
        tx = trade_service.buy(db, current_user.id, payload.grams)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return schemas.TransactionOut.model_validate(tx)


@router.post("/sell", response_model=schemas.TransactionOut)
def sell(payload: schemas.TradeIn, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    try:
        tx = trade_service.sell(db, current_user.id, payload.grams)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return schemas.TransactionOut.model_validate(tx)


@router.post("/recharge", response_model=schemas.TransactionOut)
def recharge(payload: schemas.RechargeIn, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    tx = trade_service.recharge(db, current_user.id, payload.amount, payload.note or "")
    return schemas.TransactionOut.model_validate(tx)


@router.get("/transactions", response_model=list[schemas.TransactionOut])
def transactions(skip: int = 0, limit: int = 100, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(models.Transaction).filter(models.Transaction.user_id == current_user.id)\
        .order_by(models.Transaction.id.desc()).offset(skip).limit(limit).all()
    return [schemas.TransactionOut.model_validate(r) for r in rows]
