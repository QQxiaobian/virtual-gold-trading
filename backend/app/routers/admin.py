"""后台管理路由：用户管理、资金调整、费率配置、全局流水与手续费统计。"""
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from .. import models, schemas
from ..auth import get_current_admin, hash_password
from ..database import get_db
from ..services import trade_service, config_service

router = APIRouter(prefix="/api/admin", tags=["后台管理"])


# ---------- 用户管理 ----------
@router.get("/users", response_model=list[schemas.UserOut])
def list_users(admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    return [schemas.UserOut.model_validate(u) for u in db.query(models.User).order_by(models.User.id).all()]


@router.post("/users", response_model=schemas.UserOut)
def create_user(payload: schemas.UserCreate, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    if db.query(models.User).filter(models.User.username == payload.username).first():
        raise HTTPException(status_code=400, detail="用户名已存在")
    user = models.User(
        username=payload.username, password_hash=hash_password(payload.password),
        nickname=payload.nickname or payload.username, role="user", is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return schemas.UserOut.model_validate(user)


@router.put("/users/{user_id}/active")
def toggle_user(user_id: int, is_active: bool, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")
    user.is_active = is_active
    db.commit()
    return {"ok": True, "is_active": is_active}


@router.put("/users/{user_id}/password")
def reset_password(user_id: int, new_password: str, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")
    user.password_hash = hash_password(new_password)
    db.commit()
    return {"ok": True}


# ---------- 资金调整 ----------
@router.post("/adjust", response_model=schemas.TransactionOut)
def adjust(payload: schemas.AdjustIn, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    try:
        tx = trade_service.adjust(db, payload.user_id, payload.amount, payload.note or "")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return schemas.TransactionOut.model_validate(tx)


# ---------- 费率配置 ----------
@router.get("/fee-config", response_model=schemas.FeeConfigOut)
def get_fee_config(admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    return schemas.FeeConfigOut(**config_service.get_fee_config(db))


@router.put("/fee-config")
def update_fee_config(payload: dict, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    """payload: {"key": "value", ...}，key 必须是已知配置项。"""
    allowed = set(config_service.DEFAULT_CONFIGS.keys()) - {"price_interval"}
    for key, value in payload.items():
        if key not in allowed:
            raise HTTPException(status_code=400, detail=f"不允许修改的配置项: {key}")
        row = db.query(models.SystemConfig).filter(models.SystemConfig.key == key).first()
        if row:
            row.value = str(value)
        else:
            db.add(models.SystemConfig(key=key, value=str(value)))
    db.commit()
    return schemas.FeeConfigOut(**config_service.get_fee_config(db))


@router.get("/configs", response_model=list[schemas.ConfigItem])
def list_configs(admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    return [schemas.ConfigItem(key=c.key, value=c.value, description=c.description)
            for c in db.query(models.SystemConfig).order_by(models.SystemConfig.key).all()]


# ---------- 全局流水与统计 ----------
@router.get("/transactions", response_model=list[schemas.TransactionOut])
def all_transactions(skip: int = 0, limit: int = 200, user_id: int | None = None,
                     admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    q = db.query(models.Transaction)
    if user_id:
        q = q.filter(models.Transaction.user_id == user_id)
    rows = q.order_by(models.Transaction.id.desc()).offset(skip).limit(limit).all()
    return [schemas.TransactionOut.model_validate(r) for r in rows]


@router.get("/statistics")
def statistics(days: int = 30, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    """全局手续费收入、交易笔数、按用户手续费统计。"""
    since = datetime.now() - timedelta(days=days)
    base = db.query(models.Transaction).filter(models.Transaction.created_at >= since)
    total_fee = base.with_entities(func.coalesce(func.sum(models.Transaction.fee), 0.0)).scalar()
    buy_count = base.filter(models.Transaction.type == "buy").count()
    sell_count = base.filter(models.Transaction.type == "sell").count()
    recharge_total = base.filter(models.Transaction.type == "recharge")\
        .with_entities(func.coalesce(func.sum(models.Transaction.amount), 0.0)).scalar()

    per_user = db.query(
        models.Transaction.user_id,
        func.coalesce(func.sum(models.Transaction.fee), 0.0).label("fee"),
        func.count(models.Transaction.id).label("count"),
    ).filter(models.Transaction.created_at >= since)\
        .group_by(models.Transaction.user_id).all()
    user_fees = []
    for uid, fee, count in per_user:
        u = db.query(models.User).filter(models.User.id == uid).first()
        user_fees.append({"user_id": uid, "username": u.username if u else str(uid),
                          "fee": round(fee, 2), "transactions": count})

    return {
        "days": days,
        "total_fee": round(total_fee, 2),
        "buy_count": buy_count,
        "sell_count": sell_count,
        "recharge_total": round(recharge_total, 2),
        "user_fees": user_fees,
    }
