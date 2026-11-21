"""核心逻辑测试：不依赖 HTTP，直接测交易服务与手续费计算。

运行： cd backend && .venv/bin/python ../tests/test_core.py
"""
import os
import sys

# 让脚本能 import backend/app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

# 使用临时测试数据库
os.environ["DATABASE_URL"] = "sqlite:////tmp/gold_test.db"
os.environ["SECRET_KEY"] = "test-secret-key-for-unit-test-only"

# 清除缓存的 settings（env 覆盖）
from app.config import get_settings
get_settings.cache_clear()

from app.database import Base, engine, SessionLocal
from app import models
from app.services import config_service, trade_service

Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)
db = SessionLocal()
config_service.init_configs(db)

# 建测试用户
user = models.User(username="tester", password_hash="x", nickname="测试", role="user")
db.add(user)
db.commit()
db.refresh(user)
uid = user.id


def section(title):
    print(f"\n===== {title} =====")


def show(label, p):
    print(f"{label}: 余额={p['balance']:.2f} 克重={p['grams']:.4f} 成本均价={p['avg_cost']:.2f} "
          f"市值={p['market_value']:.2f} 持盈={p['holding_pnl']:.2f} 实盈={p['realized_pnl']:.2f} 今日={p['today_pnl']:.2f}")


# ---------- 1. 充值 ----------
section("1. 虚拟充值")
trade_service.recharge(db, uid, 20000, "测试充值")
p = trade_service.get_portfolio(db, uid, 800.0)
show("充值2万", p)
assert p["balance"] == 20000.0

# ---------- 2. 百分比费率买入 ----------
section("2. 百分比费率买入（0.1%，成本含手续费）")
tx = trade_service.buy(db, uid, 10, price=800.0)
print(f"买入流水: amount={tx.amount} fee={tx.fee} fee_desc={tx.fee_desc}")
# 成交额 8000，费 8，总成本 8008 → 均价 800.8
p = trade_service.get_portfolio(db, uid, 800.0)
show("买入10克@800", p)
assert abs(tx.fee - 8.0) < 0.01, f"手续费应为8，实际{tx.fee}"
assert abs(p["avg_cost"] - 800.8) < 0.01, f"成本均价应为800.8，实际{p['avg_cost']}"
assert abs(p["balance"] - 11992.0) < 0.01, f"余额应为11992，实际{p['balance']}"

# ---------- 3. 切换为按克固定费率买入 ----------
section("3. 切换按克固定费率（买入每克2元）")
db.query(models.SystemConfig).filter(models.SystemConfig.key == "fee_mode").first().value = "per_gram"
db.query(models.SystemConfig).filter(models.SystemConfig.key == "buy_fee_per_gram").first().value = "2.0"
db.commit()
tx = trade_service.buy(db, uid, 5, price=800.0)
print(f"买入流水: amount={tx.amount} fee={tx.fee} fee_desc={tx.fee_desc}")
assert abs(tx.fee - 10.0) < 0.01, f"手续费应为10(5克×2元)，实际{tx.fee}"
p = trade_service.get_portfolio(db, uid, 800.0)
show("再买5克@800", p)
# 总成本 8008 + 4010 = 12018，总克重15 → 均价801.2
assert abs(p["avg_cost"] - 801.2) < 0.01, f"成本均价应为801.2，实际{p['avg_cost']}"

# ---------- 4. 卖出（百分比费率）----------
section("4. 卖出（0.2% 费率，移动加权成本结转）")
db.query(models.SystemConfig).filter(models.SystemConfig.key == "fee_mode").first().value = "percent"
db.commit()
tx = trade_service.sell(db, uid, 10, price=900.0)
print(f"卖出流水: amount={tx.amount} fee={tx.fee} realized={tx.realized_pnl} fee_desc={tx.fee_desc}")
# 成交额9000，费18，净到账8982；卖出成本=10×801.2=8012；已实现=970
assert abs(tx.fee - 18.0) < 0.01, f"卖出手续费应为18，实际{tx.fee}"
assert abs(tx.realized_pnl - 970.0) < 0.01, f"已实现盈亏应为970，实际{tx.realized_pnl}"
p = trade_service.get_portfolio(db, uid, 900.0)
show("卖出10克@900", p)
assert abs(p["grams"] - 5.0) < 0.001
assert abs(p["realized_pnl"] - 970.0) < 0.01

# ---------- 5. 最低手续费 ----------
section("5. 最低手续费（最低10元）")
db.query(models.SystemConfig).filter(models.SystemConfig.key == "min_fee").first().value = "10"
db.commit()
tx = trade_service.buy(db, uid, 0.1, price=800.0)
print(f"小额买入 fee={tx.fee} fee_desc={tx.fee_desc}")
assert abs(tx.fee - 10.0) < 0.01, f"最低手续费应为10，实际{tx.fee}"

# ---------- 6. 余额不足保护 ----------
section("6. 余额不足保护")
try:
    trade_service.buy(db, uid, 100000, price=800.0)
    print("ERROR: 未抛异常")
    assert False
except ValueError as e:
    print(f"正确拦截: {e}")

# ---------- 7. 持仓不足保护 ----------
section("7. 持仓不足保护")
try:
    trade_service.sell(db, uid, 9999, price=800.0)
    print("ERROR: 未抛异常")
    assert False
except ValueError as e:
    print(f"正确拦截: {e}")

# ---------- 8. 后台资金调整 ----------
section("8. 后台资金调整")
tx = trade_service.adjust(db, uid, 500, "后台奖励")
p = trade_service.get_portfolio(db, uid, 900.0)
show("调整+500", p)

print("\n===== 全部测试通过 ✅ =====")
db.close()
os.remove("/tmp/gold_test.db")
