"""金价抓取服务：新浪上金所 Au99.99（元/克）为主源，AUTD 备用，gold-api 国际参考。

新浪接口需带 Referer 防盗链头；品种代码必须大写（小写返回空）。
"""
import re
import json
import math
import httpx
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from ..config import settings
from .. import models

SINA_URL = "https://hq.sinajs.cn/list={symbol}"
SINA_HEADERS = {
    "Referer": "https://finance.sina.com.cn/",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
}
SINA_XAU_KLINE = ("https://stock2.finance.sina.com.cn/futures/api/jsonp.php/"
                  "var%20_t=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=XAU")


def _parse_sina(text: str) -> float | None:
    """从 var hq_str_xxx="a,b,c,..."; 中解析当前价（第 1 个字段）。"""
    m = re.search(r'="([^"]*)"', text)
    if not m:
        return None
    parts = m.group(1).split(",")
    if len(parts) < 2 or not parts[0]:
        return None
    try:
        price = float(parts[0])
        return price if price > 0 else None
    except ValueError:
        return None


def fetch_sina_price(symbol: str | None = None) -> float | None:
    sym = symbol or settings.SINA_GOLD_SYMBOL
    try:
        with httpx.Client(timeout=10, follow_redirects=True) as client:
            r = client.get(SINA_URL.format(symbol=sym), headers=SINA_HEADERS)
            r.encoding = "gbk"
            price = _parse_sina(r.text)
            if price:
                return price
    except Exception:
        pass
    return None


def fetch_all_prices() -> dict:
    """返回各数据源价格，供展示与交叉校验。"""
    result = {"sina_au9999": None, "sina_autd": None, "international_per_gram": None}
    result["sina_au9999"] = fetch_sina_price("gds_AU9999")
    if result["sina_au9999"] is None:
        result["sina_au9999"] = fetch_sina_price("gds_AUTD")
    result["sina_autd"] = fetch_sina_price("gds_AUTD")
    try:
        with httpx.Client(timeout=10) as client:
            r = client.get("https://api.gold-api.com/price/XAU")
            if r.status_code == 200:
                usd_oz = r.json().get("price")
                if usd_oz:
                    result["international_per_gram"] = round(usd_oz / 31.1035, 2)
    except Exception:
        pass
    return result


def _store_sina_point(db: Session, price: float, min_gap_seconds: int = 120) -> bool:
    """实时点入库去重：价格未变且距上一条 sina 点不足 min_gap_seconds 秒则跳过。

    避免每 30 秒抓一次、价格不变时无限堆积同价点，把历史走势图右半段挤成一条直线。
    """
    last = db.query(models.PriceHistory).filter(
        models.PriceHistory.source == "sina"
    ).order_by(models.PriceHistory.id.desc()).first()
    if last:
        gap = (datetime.now() - last.created_at).total_seconds()
        if abs(last.price - price) < 1e-6 and 0 <= gap < min_gap_seconds:
            return False
    db.add(models.PriceHistory(price=price, source="sina"))
    db.commit()
    return True


def get_current_price(db: Session) -> float:
    """当前成交价：优先实时抓取，失败则用数据库最近一条历史价。"""
    price = fetch_sina_price()
    if price:
        _store_sina_point(db, price)
        return price
    last = db.query(models.PriceHistory).order_by(models.PriceHistory.id.desc()).first()
    return last.price if last else 0.0


def fetch_and_store(db: Session) -> float | None:
    """定时任务调用：抓取并入库，返回价格。"""
    price = fetch_sina_price()
    if price:
        _store_sina_point(db, price)
    return price


def _spread(db: Session) -> float:
    """买卖点差比例（可后台配置 buy_sell_spread，默认 0.0006）。"""
    from . import config_service
    try:
        raw = config_service.get_value(db, "buy_sell_spread")
        return max(0.0, float(raw)) if raw is not None else 0.0006
    except Exception:
        return 0.0006


def get_quote(db: Session) -> dict:
    """返回实时买入价/卖出价/中间价。

    买入价 = 中间价 ×(1+点差)，卖出价 = 中间价 ×(1-点差)。
    成交仍按中间价，避免与成本/盈亏账目 logic 冲突；此处仅用于展示。
    """
    mid = get_current_price(db)
    sp = _spread(db)
    buy = round(mid * (1 + sp), 2)
    sell = round(mid * (1 - sp), 2)
    last = db.query(models.PriceHistory).order_by(models.PriceHistory.id.desc()).first()
    return {
        "price": mid,
        "buy_price": buy,
        "sell_price": sell,
        "spread": sp,
        "source": "sina(Au99.99)",
        "updated_at": last.created_at if last else None,
    }


def _safe_float(v) -> float | None:
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def _fetch_xau_closes(days: int) -> list[tuple[str, float]]:
    """拉取新浪 XAU 日K（美元/盎司）。失败返回空列表。"""
    try:
        with httpx.Client(timeout=15, follow_redirects=True) as client:
            r = client.get(SINA_XAU_KLINE, headers=SINA_HEADERS)
        m = re.search(r"=\((.*)\);?$", r.text.strip(), re.S) or re.search(r"=\((.*)\)", r.text, re.S)
        if not m:
            return []
        rows = json.loads(m.group(1))
        if not isinstance(rows, list) or not rows:
            return []
        rows = rows[-days:]
        return [(row["date"], float(row["close"])) for row in rows
                if row.get("date") and _safe_float(row.get("close"))]
    except Exception as e:
        print(f"[backfill] XAU 拉取失败: {e}")
        return []


def _synthetic_closes(days: int, anchor: float) -> list[tuple[str, float]]:
    """合成历史收盘价：以当前价为终点，向后按确定性波动反推，保证走势图有数据。

    用于外部历史接口不可达时的兜底（NAS 网络受限场景）。
    """
    closes = []
    today = datetime.now().date()
    # 从 1 年前 ~ 现在，anchor 为今天价格；模拟长期温和上涨 + 中期波动
    n = days
    for i in range(n):
        d = today - timedelta(days=(n - 1 - i))
        t = i / max(1, n - 1)  # 0..1，越接近 1 越靠近今天
        # 基线：一年前约为今天的 78%，线性升到今天
        base = anchor * (0.78 + 0.22 * t)
        # 叠加多个正弦波形成自然波动，末端归零保证锚定当天
        wave = (math.sin(i / 11.0) * 0.018 + math.sin(i / 29.0 + 1.2) * 0.012
                + math.sin(i / 4.5 + 0.7) * 0.004)
        wave *= (1.0 - t)  # 越靠近今天波动越小，末端精确锚定
        closes.append((d.isoformat(), round(base * (1 + wave), 2)))
    return closes


def backfill_history(db: Session, days: int = 400) -> int:
    """首次部署时回填历史走势数据（日级）。

    优先用新浪 XAU 日K 按当前价缩放对齐为元/克（保留真实涨跌形状）；
    外部接口不可达时用确定性合成数据兜底，确保近1月/3月/半年/1年走势图都有数据。
    已存在的同日记录跳过，避免重复。
    """
    anchor = fetch_sina_price()
    last = db.query(models.PriceHistory).order_by(models.PriceHistory.id.desc()).first()
    if not anchor and last:
        anchor = last.price
    if not anchor:
        anchor = 700.0  # 极端兜底

    closes = _fetch_xau_closes(days)
    use_synthetic = False
    if closes:
        latest_xau = closes[-1][1]
        ratio = anchor / latest_xau if latest_xau else 1.0
        closes = [(d, round(c * ratio, 2)) for d, c in closes]
    else:
        use_synthetic = True
        closes = _synthetic_closes(min(days, 400), anchor)

    existing = {row[0].date() for row in db.query(models.PriceHistory.created_at).all()}
    added = 0
    for date_str, close in closes:
        try:
            dt = datetime.strptime(date_str[:10], "%Y-%m-%d")
        except (ValueError, TypeError):
            continue
        if dt.date() in existing:
            continue
        db.add(models.PriceHistory(
            price=close, source="xau_backfill" if not use_synthetic else "synthetic_backfill",
            created_at=dt,
        ))
        added += 1
    if added:
        db.commit()
    print(f"[backfill] 回填 {added} 条历史（{'合成兜底' if use_synthetic else 'XAU真实'}）")
    return added


def get_today_open(db: Session) -> float:
    """今日开盘参考价：取今日第一条历史价，无则取最近一条。"""
    today = datetime.now().date()
    rows = db.query(models.PriceHistory).filter(
        models.PriceHistory.created_at >= datetime.combine(today, datetime.min.time())
    ).order_by(models.PriceHistory.id.asc()).all()
    if rows:
        return rows[0].price
    last = db.query(models.PriceHistory).order_by(models.PriceHistory.id.desc()).first()
    return last.price if last else 0.0
