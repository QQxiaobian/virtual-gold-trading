"""虚拟黄金交易系统 - FastAPI 主入口。"""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .database import Base, engine, SessionLocal
from . import models
from .auth import hash_password
from .services import config_service, scheduler
from .routers import auth, market, trade, admin


def init_db():
    """建表 + 初始化配置 + 创建初始管理员。"""
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        config_service.init_configs(db)
        if not db.query(models.User).filter(models.User.username == settings.INIT_ADMIN_USERNAME).first():
            db.add(models.User(
                username=settings.INIT_ADMIN_USERNAME,
                password_hash=hash_password(settings.INIT_ADMIN_PASSWORD),
                nickname="管理员", role="admin", is_active=True,
            ))
            db.commit()
            print(f"[init] 已创建初始管理员 {settings.INIT_ADMIN_USERNAME} / {settings.INIT_ADMIN_PASSWORD}（请尽快修改）")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    scheduler.start_scheduler()
    yield
    scheduler.stop_scheduler()


app = FastAPI(title=settings.APP_NAME, version=settings.VERSION, lifespan=lifespan)

# CORS：开发/自用允许所有来源；生产建议收紧到 NAS 地址
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(market.router)
app.include_router(trade.router)
app.include_router(admin.router)


@app.get("/")
def root():
    return {"name": settings.APP_NAME, "version": settings.VERSION, "docs": "/docs"}


@app.get("/api/health")
def health():
    return {"status": "ok", "version": settings.VERSION}
