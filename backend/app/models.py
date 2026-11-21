"""SQLAlchemy 数据模型：多用户、资金、持仓、流水、金价历史、系统配置。"""
from datetime import datetime
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, UniqueConstraint
from .database import Base


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    nickname = Column(String(50), default="")
    role = Column(String(10), default="user", nullable=False)  # user / admin
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.now, nullable=False)


class Account(Base):
    """资金账户：一个用户一个账户。"""
    __tablename__ = "accounts"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, unique=True, index=True)
    balance = Column(Float, default=0.0, nullable=False)  # 可用资金（元）
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)


class Holding(Base):
    """持仓：一个用户一条汇总记录，成本均价 = cost_amount / grams。"""
    __tablename__ = "holdings"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, unique=True, index=True)
    grams = Column(Float, default=0.0, nullable=False)         # 持仓克重
    cost_amount = Column(Float, default=0.0, nullable=False)   # 总成本（含买入手续费）
    realized_pnl = Column(Float, default=0.0, nullable=False)  # 累计已实现盈亏
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)


class Transaction(Base):
    """资金/交易流水：每一笔充值、买入、卖出、后台调整都留痕。"""
    __tablename__ = "transactions"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    type = Column(String(12), nullable=False)  # recharge / buy / sell / adjust
    amount = Column(Float, nullable=False)     # 资金变动：正=入账，负=出账
    grams = Column(Float, default=0.0)         # 克重变动：正=买入，负=卖出
    price = Column(Float, default=0.0)         # 成交金价（元/克）
    fee = Column(Float, default=0.0)           # 手续费（元）
    fee_desc = Column(String(100), default="") # 手续费计算说明
    balance_after = Column(Float, nullable=False)
    realized_pnl = Column(Float, default=0.0)  # 已实现盈亏（卖出时）
    note = Column(String(200), default="")
    created_at = Column(DateTime, default=datetime.now, nullable=False, index=True)


class PriceHistory(Base):
    """金价历史：定时抓取累积，供走势图使用。"""
    __tablename__ = "price_history"
    id = Column(Integer, primary_key=True, index=True)
    price = Column(Float, nullable=False)      # 元/克
    source = Column(String(20), default="sina")
    created_at = Column(DateTime, default=datetime.now, nullable=False, index=True)


class SystemConfig(Base):
    """系统配置：后台可调参数，key-value 存储。"""
    __tablename__ = "system_config"
    key = Column(String(50), primary_key=True)
    value = Column(String(200), nullable=False)
    description = Column(String(200), default="")
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)
