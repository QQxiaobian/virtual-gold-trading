"""系统配置读写与手续费计算。"""
from sqlalchemy.orm import Session
from .. import models
from ..config import settings

# 默认配置（首次启动写入；后台可改）
DEFAULT_CONFIGS = {
    "fee_mode": (settings.DEFAULT_FEE_MODE, "计费方式：percent=按金额百分比 / per_gram=按克固定"),
    "buy_fee_rate": (str(settings.DEFAULT_BUY_FEE_RATE), "买入费率（百分比小数，如 0.001=0.1%）"),
    "sell_fee_rate": (str(settings.DEFAULT_SELL_FEE_RATE), "卖出费率（百分比小数，如 0.002=0.2%）"),
    "buy_fee_per_gram": (str(settings.DEFAULT_BUY_FEE_PER_GRAM), "买入每克固定手续费（元）"),
    "sell_fee_per_gram": (str(settings.DEFAULT_SELL_FEE_PER_GRAM), "卖出每克固定手续费（元）"),
    "min_fee": (str(settings.DEFAULT_MIN_FEE), "单笔最低手续费（元）"),
    "price_interval": (str(settings.PRICE_FETCH_INTERVAL_SECONDS), "金价抓取间隔（秒）"),
}


def init_configs(db: Session):
    """首次启动初始化配置项（已存在的不覆盖）。"""
    for key, (value, desc) in DEFAULT_CONFIGS.items():
        if not db.query(models.SystemConfig).filter(models.SystemConfig.key == key).first():
            db.add(models.SystemConfig(key=key, value=value, description=desc))
    db.commit()


def get_config(db: Session, key: str, default: str = "") -> str:
    row = db.query(models.SystemConfig).filter(models.SystemConfig.key == key).first()
    return row.value if row else default


def get_float(db: Session, key: str, default: float = 0.0) -> float:
    try:
        return float(get_config(db, key, str(default)))
    except (ValueError, TypeError):
        return default


def get_fee_config(db: Session) -> dict:
    return {
        "fee_mode": get_config(db, "fee_mode", settings.DEFAULT_FEE_MODE),
        "buy_fee_rate": get_float(db, "buy_fee_rate", settings.DEFAULT_BUY_FEE_RATE),
        "sell_fee_rate": get_float(db, "sell_fee_rate", settings.DEFAULT_SELL_FEE_RATE),
        "buy_fee_per_gram": get_float(db, "buy_fee_per_gram", settings.DEFAULT_BUY_FEE_PER_GRAM),
        "sell_fee_per_gram": get_float(db, "sell_fee_per_gram", settings.DEFAULT_SELL_FEE_PER_GRAM),
        "min_fee": get_float(db, "min_fee", settings.DEFAULT_MIN_FEE),
    }


def calculate_fee(db: Session, side: str, amount: float, grams: float) -> tuple[float, str]:
    """按当前配置计算手续费，返回 (手续费, 说明)。"""
    cfg = get_fee_config(db)
    mode = cfg["fee_mode"]
    min_fee = cfg["min_fee"]
    if mode == "per_gram":
        rate = cfg[f"{side}_fee_per_gram"]
        fee = grams * rate
        desc = f"固定每克 {rate} 元 × {grams:.4f} 克"
    else:  # percent
        rate = cfg[f"{side}_fee_rate"]
        fee = amount * rate
        desc = f"费率 {rate * 100:.3f}% × 成交额 {amount:.2f} 元"
    if fee < min_fee:
        fee = min_fee
        desc += f"（低于最低收费 {min_fee} 元，按最低收取）"
    return round(fee, 2), desc
