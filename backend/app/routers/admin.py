"""后台管理路由：用户管理、资金调整、费率配置、全局流水与手续费统计。"""
import io
import csv
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import func
from .. import models, schemas
from ..auth import get_current_admin, hash_password, decode_token_user
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


@router.delete("/users/{user_id}")
def delete_user(user_id: int, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    """删除账号及其账户、持仓、流水数据（不可删除管理员自己）。"""
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="不能删除当前管理员账号")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")
    db.query(models.Account).filter(models.Account.user_id == user_id).delete(synchronize_session=False)
    db.query(models.Holding).filter(models.Holding.user_id == user_id).delete(synchronize_session=False)
    db.query(models.Transaction).filter(models.Transaction.user_id == user_id).delete(synchronize_session=False)
    db.delete(user)
    db.commit()
    return {"ok": True}


@router.get("/users/{user_id}/detail")
def user_detail(user_id: int, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    """查看单个用户的账户明细：基本信息 + 资金/持仓 + 收益 + 流水。"""
    from ..services import price_service
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")
    price = price_service.get_current_price(db)
    portfolio = trade_service.get_portfolio(db, user_id, price)
    txs = db.query(models.Transaction).filter(models.Transaction.user_id == user_id)\
        .order_by(models.Transaction.id.desc()).limit(200).all()
    return {
        "user": schemas.UserOut.model_validate(user).model_dump(),
        "portfolio": portfolio,
        "transactions": [schemas.TransactionOut.model_validate(t).model_dump() for t in txs],
    }


@router.post("/users/{user_id}/reset-balance")
def api_reset_balance(user_id: int, payload: dict, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    try:
        amount = float(payload.get("amount"))
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="金额无效")
    try:
        return trade_service.reset_balance(db, user_id, amount, payload.get("note", ""))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/undo-recharge/{tx_id}")
def undo_recharge(tx_id: int, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    try:
        rtx = trade_service.undo_recharge(db, tx_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return schemas.TransactionOut.model_validate(rtx)


@router.post("/reset-fee-records")
def reset_fee_records(admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    return trade_service.reset_fee_records(db)


@router.get("/export-transactions")
def export_transactions(request: Request, user_id: int | None = None, days: int | None = None,
                        token: str | None = None, db: Session = Depends(get_db)):
    """导出流水为 CSV（可按用户、天数筛选）。

    鉴权：优先 Authorization Header；浏览器直接打开下载链接时可在 query 传 token。
    """
    admin = None
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        admin = decode_token_user(auth_header[7:], db)
    elif token:
        admin = decode_token_user(token, db)
    if not admin or admin.role != "admin":
        raise HTTPException(status_code=401, detail="需要管理员权限")

    q = db.query(models.Transaction)
    if user_id:
        q = q.filter(models.Transaction.user_id == user_id)
    if days:
        q = q.filter(models.Transaction.created_at >= datetime.now() - timedelta(days=days))
    rows = q.order_by(models.Transaction.id.asc()).all()
    user_names = {u.id: u.username for u in db.query(models.User).all()}

    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["ID", "用户ID", "用户名", "类型", "资金变动(元)", "克重(克)", "成交价(元/克)",
                "手续费(元)", "手续费说明", "余额(元)", "已实现盈亏(元)", "已退款", "备注", "时间"])
    type_map = {"recharge": "充值", "buy": "买入", "sell": "卖出", "adjust": "调整", "refund": "退款"}
    for r in rows:
        w.writerow([r.id, r.user_id, user_names.get(r.user_id, ""), type_map.get(r.type, r.type),
                    r.amount, r.grams, r.price, r.fee, r.fee_desc, r.balance_after,
                    r.realized_pnl, "是" if r.refunded else "否", r.note,
                    r.created_at.strftime("%Y-%m-%d %H:%M:%S")])
    content = "\ufeff" + out.getvalue()  # BOM 保证 Excel 打开中文不乱码
    filename = f"transactions_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    return StreamingResponse(
        iter([content.encode("utf-8")]), media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------- 资金调整 ----------
@router.post("/adjust", response_model=schemas.TransactionOut)
def adjust(payload: schemas.AdjustIn, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    try:
        tx = trade_service.adjust(db, payload.user_id, payload.amount, payload.note or "")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return schemas.TransactionOut.model_validate(tx)


# ---------- 退款（撤销交易） ----------
@router.post("/refund/{tx_id}", response_model=schemas.TransactionOut)
def refund_transaction(tx_id: int, admin: models.User = Depends(get_current_admin), db: Session = Depends(get_db)):
    try:
        rtx = trade_service.refund(db, tx_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return schemas.TransactionOut.model_validate(rtx)


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
