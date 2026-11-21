"""后台定时任务：按配置间隔抓取金价入库。"""
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy.orm import Session
from ..database import SessionLocal
from ..config import settings
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


def start_scheduler():
    global _scheduler
    if _scheduler is not None:
        return
    _scheduler = BackgroundScheduler(timezone="Asia/Shanghai")
    _scheduler.add_job(_job, IntervalTrigger(seconds=settings.PRICE_FETCH_INTERVAL_SECONDS),
                       id="fetch_price", replace_existing=True)
    _scheduler.start()
    # 启动即抓一次
    _job()
    print(f"[scheduler] 金价抓取已启动，间隔 {settings.PRICE_FETCH_INTERVAL_SECONDS}s")


def stop_scheduler():
    global _scheduler
    if _scheduler:
        _scheduler.shutdown(wait=False)
        _scheduler = None
