"""虚拟黄金交易系统 - FastAPI 主入口。"""
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from .config import settings
from .database import Base, engine, SessionLocal
from . import models
from .auth import hash_password
from .services import config_service, scheduler
from .routers import auth, market, trade, admin

# Web 静态文件目录：Docker 镜像内由 Dockerfile COPY 到 /app/web。
# 本地开发时可通过 WEB_DIR 环境变量指向 app/build/web。
WEB_DIR = os.environ.get("WEB_DIR", "/app/web")
_web_index = os.path.join(WEB_DIR, "index.html")


def _migrate():
    """轻量迁移：为已有 SQLite 库补齐新增列（避免旧库缺列报错）。"""
    with engine.connect() as conn:
        cols = {row[1] for row in conn.execute(text("PRAGMA table_info(transactions)")).fetchall()}
        if "refunded" not in cols:
            conn.execute(text("ALTER TABLE transactions ADD COLUMN refunded BOOLEAN NOT NULL DEFAULT 0"))
            conn.commit()


def init_db():
    """建表 + 迁移 + 初始化配置 + 创建初始管理员。"""
    Base.metadata.create_all(bind=engine)
    _migrate()
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


@app.get("/api/health")
def health():
    return {"status": "ok", "version": settings.VERSION}


# ---------- 托管 Flutter Web 静态站点 ----------
# Mount 必须在所有 API 路由注册之后；StaticFiles(html=True) 让 / 返回 index.html。
if os.path.isdir(WEB_DIR):
    # 先挂载具体静态资源目录（assets、icons、flutter.js 等由 StaticFiles 处理）
    app.mount("/assets", StaticFiles(directory=os.path.join(WEB_DIR, "assets")), name="assets") if os.path.isdir(os.path.join(WEB_DIR, "assets")) else None
    app.mount("/icons", StaticFiles(directory=os.path.join(WEB_DIR, "icons")), name="icons") if os.path.isdir(os.path.join(WEB_DIR, "icons")) else None

    # 禁用浏览器缓存：自用内网系统无需缓存，避免部署新版后浏览器仍加载旧的
    # main.dart.js / index.html（尤其曾注册过 service worker 的设备）。
    _no_cache = {
        "Cache-Control": "no-cache, no-store, must-revalidate",
        "Pragma": "no-cache",
        "Expires": "0",
    }

    @app.get("/{full_path:path}", include_in_schema=False)
    def web_spa(full_path: str):
        """单页应用回退：优先返回真实静态文件，否则返回 index.html。"""
        # 规范化路径，防止目录穿越
        candidate = os.path.normpath(os.path.join(WEB_DIR, full_path))
        if candidate.startswith(WEB_DIR) and os.path.isfile(candidate):
            return FileResponse(candidate, headers=_no_cache)
        if os.path.isfile(_web_index):
            return FileResponse(_web_index, headers=_no_cache)
        return HTMLResponse("<h3>Web 未构建</h3>", status_code=404)
else:
    @app.get("/")
    def root_fallback():
        return {"name": settings.APP_NAME, "version": settings.VERSION, "docs": "/docs"}
