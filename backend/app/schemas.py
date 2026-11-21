"""Pydantic 请求/响应模型。"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field


# ---------- 用户 ----------
class UserCreate(BaseModel):
    username: str = Field(min_length=2, max_length=50)
    password: str = Field(min_length=6, max_length=100)
    nickname: Optional[str] = ""


class UserLogin(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: int
    username: str
    nickname: str
    role: str
    is_active: bool
    created_at: datetime
    model_config = {"from_attributes": True}


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


# ---------- 资金 ----------
class RechargeIn(BaseModel):
    amount: float = Field(gt=0, description="充值金额（元）")
    note: Optional[str] = ""


class AdjustIn(BaseModel):
    """后台资金调整：正数加钱，负数扣钱。"""
    user_id: int
    amount: float = Field(ne=0)
    note: Optional[str] = ""


# ---------- 交易 ----------
class TradeIn(BaseModel):
    grams: float = Field(gt=0, description="买卖克重")


class TransactionOut(BaseModel):
    id: int
    type: str
    amount: float
    grams: float
    price: float
    fee: float
    fee_desc: str
    balance_after: float
    realized_pnl: float
    note: str
    refunded: bool = False
    created_at: datetime
    model_config = {"from_attributes": True}


# ---------- 行情 ----------
class PriceOut(BaseModel):
    price: float
    source: str
    updated_at: Optional[datetime]


class PricePoint(BaseModel):
    time: datetime
    price: float


class PriceHistoryOut(BaseModel):
    range: str
    points: List[PricePoint]


# ---------- 持仓/账户总览 ----------
class PortfolioOut(BaseModel):
    balance: float                 # 可用资金
    grams: float                   # 持仓克重
    cost_amount: float             # 持仓总成本（含手续费）
    avg_cost: float                # 成本均价
    current_price: float           # 当前金价
    market_value: float            # 持仓市值
    holding_pnl: float             # 持仓浮动盈亏
    realized_pnl: float            # 累计已实现盈亏
    total_pnl: float               # 累计总收益 = 浮动 + 已实现
    today_pnl: float               # 今日收益（按今日开盘价估算）
    total_assets: float            # 总资产 = 资金 + 市值


# ---------- 配置 ----------
class ConfigItem(BaseModel):
    key: str
    value: str
    description: Optional[str] = ""


class ConfigUpdate(BaseModel):
    value: str


class FeeConfigOut(BaseModel):
    fee_mode: str
    buy_fee_rate: float
    sell_fee_rate: float
    buy_fee_per_gram: float
    sell_fee_per_gram: float
    min_fee: float
    allow_user_recharge: bool = False
