"""金价抓取服务：新浪上金所 Au99.99（元/克）为主源，AUTD 备用，gold-api 国际参考。

新浪接口需带 Referer 防盗链头；品种代码必须大写（小写返回空）。
返回字段（逗号分隔）：当前价, 涨跌?, 买价, 卖价, 最高, 最低, 时间, 昨收, 今开, ...
"""
import re
import json
import httpx
from datetime import datetime
from sqlalchemy.orm import Session
from ..config import settings
from .. import models

SINA_URL = "https://hq.sinajs.cn/list={symbol}"
SINA_HEADERS = {
    "Referer": "https://finance.sina.com.cn/",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
}


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
    # 主源：Au99.99
    result["sina_au9999"] = fetch_sina_price("gds_AU9999")
    # 备源：Au(T+D)
    if result["sina_au9999"] is None:
        result["sina_au9999"] = fetch_sina_price("gds_AUTD")
    result["sina_autd"] = fetch_sina_price("gds_AUTD")
    # 国际参考：美元/盎司 → 美元/克（不换算人民币，仅参考趋势）
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


def get_current_price(db: Session) -> float:
    """当前成交价：优先实时抓取，失败则用数据库最近一条历史价。"""
    price = fetch_sina_price()
    if price:
        db.add(models.PriceHistory(price=price, source="sina"))
        db.commit()
        return price
    last = db.query(models.PriceHistory).order_by(models.PriceHistory.id.desc()).first()
    return last.price if last else 0.0


def fetch_and_store(db: Session) -> float | None:
    """定时任务调用：抓取并入库，返回价格。"""
    price = fetch_sina_price()
    if price:
        db.add(models.PriceHistory(price=price, source="sina"))
        db.commit()
    return price


SINA_XAU_KLINE = ("https://stock2.finance.sina.com.cn/futures/api/jsonp.php/"
                  "var%20_t=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=XAU")


def backfill_history(db: Session, days: int = 400) -> int:
    """首次部署时回填历史走势数据。

    新浪 XAU 日K 是美元/盎司，直接用作元/克会放大约 4.7 倍。
    这里按其最新收盘价缩放对齐到当前实时金价（元/克），保留真实涨跌形状，
    末端与当前报价衔接。已存在的同日记录会跳过，避免重复。
    """
    try:
        with httpx.Client(timeout=15, follow_redirects=True) as client:
            r = client.get(SINA_XAU_KLINE, headers=SINA_HEADERS)
        m = re.search(r"=\((.*)\);?$", r.text.strip(), re.S)
        if not m:
            m = re.search(r"=\((.*)\)", r.text, re.S)
        if not m:
            return 0
        rows = json.loads(m.group(1))
        if not isinstance(rows, list) or not rows:
            return 0
        rows = rows[-days:]
        closes = [(row.get("date"), float(row["close"])) for row in rows
                  if row.get("close") and _safe_float(row["close"])]
        if not closes:
            return 0
        latest_xau = closes[-1][1]
        anchor = fetch_sina_price() or latest_xau
        ratio = anchor / latest_xau if latest_xau else 1.0

        existing = {row[0].date() for row in db.query(models.PriceHistory.created_at).all()}
        added = 0
        for date_str, close in closes:
            try:
                dt = datetime.strptime(date_str, "%Y-%m-%d")
            except (ValueError, TypeError):
                continue
            if dt.date() in existing:
                continue
            db.add(models.PriceHistory(
                price=round(close * ratio, 2), source="xau_backfill", created_at=dt,
            ))
            added += 1
        if added:
            db.commit()
        return added
    except Exception as e:
        print(f"[backfill] error: {e}")
        return 0


def _safe_float(v) -> float | None:
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


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
