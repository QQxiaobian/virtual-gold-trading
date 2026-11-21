"""交易路由：账户总览、买入、卖出、充值、流水查询。"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from .. import models, schemas
from ..auth import get_current_user
from ..database import get_db
from ..services import trade_service, price_service, config_service

router = APIRouter(prefix="/api/trade", tags=["交易"])


@router.get("/fee-config")
def public_fee_config(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    """登录用户可读的当前手续费配置（用于交易页预估），避免普通用户访问管理员接口被拒。"""
    return config_service.get_fee_config(db)


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


@router.get("/recharge-enabled")
def recharge_enabled(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    """查询当前是否允许用户自助充值（管理员始终为 True）。"""
    return {"enabled": current_user.role == "admin" or config_service.recharge_enabled(db)}


@router.post("/recharge", response_model=schemas.TransactionOut)
def recharge(payload: schemas.RechargeIn, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    if current_user.role != "admin" and not config_service.recharge_enabled(db):
        raise HTTPException(status_code=403, detail="管理员未开放充值功能，请联系管理员")
    tx = trade_service.recharge(db, current_user.id, payload.amount, payload.note or "")
    return schemas.TransactionOut.model_validate(tx)


@router.get("/transactions", response_model=list[schemas.TransactionOut])
def transactions(skip: int = 0, limit: int = 100, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(models.Transaction).filter(models.Transaction.user_id == current_user.id)\
        .order_by(models.Transaction.id.desc()).offset(skip).limit(limit).all()
    return [schemas.TransactionOut.model_validate(r) for r in rows]
