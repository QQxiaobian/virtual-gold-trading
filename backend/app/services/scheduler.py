"""后台定时任务：按配置间隔抓取金价入库。"""
from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy.orm import Session
from ..database import SessionLocal
from ..config import settings
from .. import models
from . import price_service, config_service

_scheduler: BackgroundScheduler | None = None


def _job():
    db: Session = SessionLocal()
    try:
        price_service.fetch_and_store(db)
    except Exception as e:
        print(f"[price job] error: {e}")
    finally:
        db.close()


def _backfill_job():
    """历史跨度不足一年时回填历史走势。

    注意：不能用 count 判断——实时抓取每 30 秒一条，一天就上百条，
    会导致历史回填永远被跳过，近1月/3月/半年走势图空白。
    改看最早记录距今的天数；回填函数内部按日期去重，重复调用安全。
    """
    db: Session = SessionLocal()
    try:
        first = db.query(models.PriceHistory).order_by(models.PriceHistory.created_at.asc()).first()
        span_days = (datetime.now() - first.created_at).days if first else 9999
        if span_days < 300:
            added = price_service.backfill_history(db)
            print(f"[backfill] 历史跨度 {span_days} 天，已回填 {added} 条")
        else:
            print(f"[backfill] 历史跨度 {span_days} 天，无需回填")
    except Exception as e:
        print(f"[backfill] error: {e}")
    finally:
        db.close()


import threading


def _startup_jobs():
    """首次抓取与历史回填放到后台线程，避免新浪接口超时拖慢服务启动。"""
    _job()
    _backfill_job()


def start_scheduler():
    global _scheduler
    if _scheduler is not None:
        return
    _scheduler = BackgroundScheduler(timezone="Asia/Shanghai")
    _scheduler.add_job(_job, IntervalTrigger(seconds=settings.PRICE_FETCH_INTERVAL_SECONDS),
                       id="fetch_price", replace_existing=True)
    _scheduler.start()
    # 首次抓取与回填异步执行，服务立即可用（网页/接口无需等待外部行情接口）
    threading.Thread(target=_startup_jobs, daemon=True, name="gold-startup-jobs").start()
    print(f"[scheduler] 金价抓取已启动，间隔 {settings.PRICE_FETCH_INTERVAL_SECONDS}s（首抓/回填后台进行）")


def stop_scheduler():
    global _scheduler
    if _scheduler:
        _scheduler.shutdown(wait=False)
        _scheduler = None
