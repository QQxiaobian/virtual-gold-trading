"""交易核心：买入、卖出、充值、资金调整。

关键规则（已按需求确认）：
- 手续费两种模式可后台切换：percent（按成交金额百分比）/ per_gram（按克固定），支持最低收费。
- 成本均价包含买入手续费：cost_amount 累计(成交额+买入手续费)，avg_cost = cost_amount / grams。
- 卖出按移动加权成本结转：卖出成本 = 卖出克重 × 当前成本均价；已实现盈亏 = 净到账 - 卖出成本。
- 每一笔都写 transactions 流水，全程可追溯。
"""
from datetime import datetime
from sqlalchemy.orm import Session
from .. import models
from . import config_service, price_service


def _get_or_create_account(db: Session, user_id: int) -> models.Account:
    acc = db.query(models.Account).filter(models.Account.user_id == user_id).first()
    if not acc:
        acc = models.Account(user_id=user_id, balance=0.0)
        db.add(acc)
        db.commit()
        db.refresh(acc)
    return acc


def _get_or_create_holding(db: Session, user_id: int) -> models.Holding:
    h = db.query(models.Holding).filter(models.Holding.user_id == user_id).first()
    if not h:
        h = models.Holding(user_id=user_id, grams=0.0, cost_amount=0.0, realized_pnl=0.0)
        db.add(h)
        db.commit()
        db.refresh(h)
    return h


def recharge(db: Session, user_id: int, amount: float, note: str = "") -> models.Transaction:
    """虚拟充值：仅增加可用资金并留痕。"""
    acc = _get_or_create_account(db, user_id)
    acc.balance = round(acc.balance + amount, 2)
    tx = models.Transaction(
        user_id=user_id, type="recharge", amount=amount, grams=0,
        price=0, fee=0, fee_desc="", balance_after=acc.balance,
        note=note or "虚拟充值", created_at=datetime.now(),
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)
    return tx


def adjust(db: Session, user_id: int, amount: float, note: str = "") -> models.Transaction:
    """后台资金调整：可加可扣，留痕。"""
    acc = _get_or_create_account(db, user_id)
    new_balance = round(acc.balance + amount, 2)
    if new_balance < 0:
        raise ValueError("调整后余额不能为负")
    acc.balance = new_balance
    tx = models.Transaction(
        user_id=user_id, type="adjust", amount=amount, grams=0,
        price=0, fee=0, fee_desc="", balance_after=acc.balance,
        note=note or "后台资金调整", created_at=datetime.now(),
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)
    return tx


def buy(db: Session, user_id: int, grams: float, price: float | None = None) -> models.Transaction:
    """买入黄金克数。"""
    if price is None:
        price = price_service.get_current_price(db)
    if price <= 0:
        raise ValueError("当前金价不可用，请稍后重试")

    amount = round(grams * price, 2)          # 成交金额
    fee, fee_desc = config_service.calculate_fee(db, "buy", amount, grams)
    total_cost = round(amount + fee, 2)       # 总支出（含手续费）

    acc = _get_or_create_account(db, user_id)
    if acc.balance < total_cost:
        raise ValueError(f"余额不足：需要 {total_cost:.2f} 元，当前 {acc.balance:.2f} 元")

    acc.balance = round(acc.balance - total_cost, 2)
    h = _get_or_create_holding(db, user_id)
    h.grams = round(h.grams + grams, 6)
    h.cost_amount = round(h.cost_amount + total_cost, 2)  # 成本含买入手续费

    tx = models.Transaction(
        user_id=user_id, type="buy", amount=-total_cost, grams=grams,
        price=price, fee=fee, fee_desc=fee_desc, balance_after=acc.balance,
        note=f"买入 {grams:.4f} 克 @ {price:.2f} 元/克，成交额 {amount:.2f}",
        created_at=datetime.now(),
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)
    return tx


def sell(db: Session, user_id: int, grams: float, price: float | None = None) -> models.Transaction:
    """卖出黄金克数。"""
    if price is None:
        price = price_service.get_current_price(db)
    if price <= 0:
        raise ValueError("当前金价不可用，请稍后重试")

    h = _get_or_create_holding(db, user_id)
    if h.grams + 1e-9 < grams:
        raise ValueError(f"持仓不足：持有 {h.grams:.4f} 克，尝试卖出 {grams:.4f} 克")

    amount = round(grams * price, 2)
    fee, fee_desc = config_service.calculate_fee(db, "sell", amount, grams)
    net_received = round(amount - fee, 2)     # 净到账

    avg_cost = h.cost_amount / h.grams if h.grams > 0 else 0
    sell_cost = round(avg_cost * grams, 2)    # 卖出部分成本（含买入手续费）
    realized = round(net_received - sell_cost, 2)

    h.grams = round(max(0.0, h.grams - grams), 6)
    h.cost_amount = round(h.cost_amount - sell_cost, 2)
    if h.grams < 1e-6:  # 清空时归零，避免浮点残差
        h.grams = 0.0
        h.cost_amount = 0.0
    h.realized_pnl = round(h.realized_pnl + realized, 2)

    acc = _get_or_create_account(db, user_id)
    acc.balance = round(acc.balance + net_received, 2)

    tx = models.Transaction(
        user_id=user_id, type="sell", amount=net_received, grams=-grams,
        price=price, fee=fee, fee_desc=fee_desc, balance_after=acc.balance,
        realized_pnl=realized,
        note=f"卖出 {grams:.4f} 克 @ {price:.2f} 元/克，成交额 {amount:.2f}，盈亏 {realized:.2f}",
        created_at=datetime.now(),
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)
    return tx


def refund(db: Session, tx_id: int) -> models.Transaction:
    """管理员撤销一笔 buy/sell 交易并回滚其全部影响，生成一笔 refund 流水。

    回滚规则（tx 为原交易）：
    - 撤销买入：余额退还 (成交额+手续费)= -tx.amount；持仓 -grams；成本 -(成交额+手续费)。
    - 撤销卖出：余额扣回 净到账= tx.amount；持仓 +|grams|；成本 +(tx.amount - realized)；已实现 -realized。
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not tx:
        raise ValueError("交易记录不存在")
    if tx.type not in ("buy", "sell"):
        raise ValueError("仅可撤销买入或卖出交易")
    if tx.refunded:
        raise ValueError("该交易已退款，不可重复撤销")

    acc = _get_or_create_account(db, tx.user_id)
    h = _get_or_create_holding(db, tx.user_id)

    if tx.type == "buy":
        back = round(-tx.amount, 2)          # 退还本金+手续费
        acc.balance = round(acc.balance + back, 2)
        h.grams = round(max(0.0, h.grams - tx.grams), 6)
        h.cost_amount = round(max(0.0, h.cost_amount - back), 2)
        refund_amount = back
        note = f"撤销买入 #{tx_id}：退还 {back:.2f} 元，扣回 {tx.grams:.4f} 克"
    else:  # sell
        take_back = round(tx.amount, 2)      # 扣回原净到账
        if acc.balance < take_back:
            raise ValueError(f"退款失败：当前余额 {acc.balance:.2f} 元不足以扣回 {take_back:.2f} 元")
        sell_cost = round(tx.amount - tx.realized_pnl, 2)  # 原卖出成本（含买入手续费）
        acc.balance = round(acc.balance - take_back, 2)
        h.grams = round(h.grams + abs(tx.grams), 6)
        h.cost_amount = round(h.cost_amount + sell_cost, 2)
        h.realized_pnl = round(h.realized_pnl - tx.realized_pnl, 2)
        refund_amount = -take_back
        note = f"撤销卖出 #{tx_id}：扣回 {take_back:.2f} 元，返还 {abs(tx.grams):.4f} 克"

    # 原交易标记已退款
    tx.refunded = True
    # 生成退款流水（type=refund，不计入买卖/手续费统计）
    rtx = models.Transaction(
        user_id=tx.user_id, type="refund", amount=refund_amount, grams=0,
        price=0, fee=0, fee_desc="", balance_after=acc.balance,
        note=note, created_at=datetime.now(),
    )
    db.add(rtx)
    db.commit()
    db.refresh(rtx)
    return rtx


def recharge_by_admin(db: Session, user_id: int, amount: float, note: str = "") -> models.Transaction:
    """管理员后台为用户充值（不受用户充值开关限制）。"""
    return recharge(db, user_id, amount, note or "管理员后台充值")


def undo_recharge(db: Session, tx_id: int) -> models.Transaction:
    """管理员撤销一笔充值：扣回资金、标记原流水、生成冲正流水。"""
    tx = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not tx:
        raise ValueError("充值记录不存在")
    if tx.type != "recharge":
        raise ValueError("仅可撤销充值交易")
    if tx.refunded:
        raise ValueError("该充值已撤销，不可重复操作")
    acc = _get_or_create_account(db, tx.user_id)
    # 允许扣成负数（若用户已花掉），保证账目严格对冲
    acc.balance = round(acc.balance - tx.amount, 2)
    tx.refunded = True
    rtx = models.Transaction(
        user_id=tx.user_id, type="adjust", amount=-tx.amount, grams=0,
        price=0, fee=0, fee_desc="", balance_after=acc.balance,
        note=f"撤销充值 #{tx_id}：扣回 {tx.amount:.2f} 元", created_at=datetime.now(),
    )
    db.add(rtx)
    db.commit()
    db.refresh(rtx)
    return rtx


def reset_balance(db: Session, user_id: int, amount: float, note: str = "") -> dict:
    """管理员重置账户可用资金到指定金额，差额留痕。"""
    if amount < 0:
        raise ValueError("重置金额不能为负")
    acc = _get_or_create_account(db, user_id)
    diff = round(amount - acc.balance, 2)
    acc.balance = round(amount, 2)
    if abs(diff) > 1e-9:
        tx = models.Transaction(
            user_id=user_id, type="adjust", amount=diff, grams=0,
            price=0, fee=0, fee_desc="", balance_after=acc.balance,
            note=note or f"管理员重置余额至 {amount:.2f} 元", created_at=datetime.now(),
        )
        db.add(tx)
    db.commit()
    return {"user_id": user_id, "balance": acc.balance, "delta": diff}


def reset_fee_records(db: Session) -> dict:
    """清空手续费记录：将所有流水的 fee 与 fee_desc 归零（保留流水本身）。"""
    rows = db.query(models.Transaction).filter(models.Transaction.fee != 0).all()
    count = len(rows)
    for r in rows:
        r.fee = 0.0
        r.fee_desc = ""
    db.commit()
    return {"cleared": count}


def get_portfolio(db: Session, user_id: int, current_price: float) -> dict:
    """计算账户总览与各项收益。"""
    acc = _get_or_create_account(db, user_id)
    h = _get_or_create_holding(db, user_id)
    avg_cost = h.cost_amount / h.grams if h.grams > 0 else 0.0
    market_value = round(h.grams * current_price, 2)
    holding_pnl = round(market_value - h.cost_amount, 2)
    today_open = price_service.get_today_open(db)
    today_pnl = round(h.grams * (current_price - today_open), 2) if (today_open and h.grams) else 0.0
    return {
        "balance": round(acc.balance, 2),
        "grams": round(h.grams, 6),
        "cost_amount": round(h.cost_amount, 2),
        "avg_cost": round(avg_cost, 2),
        "current_price": current_price,
        "market_value": market_value,
        "holding_pnl": holding_pnl,
        "realized_pnl": round(h.realized_pnl, 2),
        "total_pnl": round(holding_pnl + h.realized_pnl, 2),
        "today_pnl": today_pnl,
        "total_assets": round(acc.balance + market_value, 2),
    }
