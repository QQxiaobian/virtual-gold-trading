"""应用配置：全部可通过环境变量覆盖，便于 Docker 部署。"""
import os
from pydantic_settings import BaseSettings
from functools import lru_cache


def _read_version() -> str:
    """优先读项目根的 VERSION 文件，避免版本号写死导致显示旧版本。"""
    for p in (os.environ.get("VERSION_FILE"), "/app/VERSION", "VERSION"):
        if p and os.path.isfile(p):
            try:
                v = open(p, encoding="utf-8").read().strip()
                if v:
                    return v
            except OSError:
                pass
    return "1.2.0"


class Settings(BaseSettings):
    # 基础
    APP_NAME: str = "虚拟黄金交易系统"
    VERSION: str = _read_version()
    DEBUG: bool = False

    # 安全：部署时务必修改为随机长字符串
    SECRET_KEY: str = "DEV-ONLY-CHANGE-ME-please-use-a-random-64-char-string"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 天

    # 数据库
    DATABASE_URL: str = "sqlite:///./data/gold.db"

    # 金价抓取
    PRICE_FETCH_INTERVAL_SECONDS: int = 30
    SINA_GOLD_SYMBOL: str = "gds_AU9999"  # 上金所 Au99.99，元/克（必须大写）

    # 初始手续费配置（后台可改）
    DEFAULT_FEE_MODE: str = "percent"   # percent=按金额百分比 | per_gram=按克固定
    DEFAULT_BUY_FEE_RATE: float = 0.001   # 买入 0.1%
    DEFAULT_SELL_FEE_RATE: float = 0.002  # 卖出 0.2%
    DEFAULT_BUY_FEE_PER_GRAM: float = 0.5  # 买入每克固定 0.5 元
    DEFAULT_SELL_FEE_PER_GRAM: float = 0.5  # 卖出每克固定 0.5 元
    DEFAULT_MIN_FEE: float = 0.0

    # 用户充值开关：默认关闭，需管理员在后台开启后普通用户才能自助充值
    DEFAULT_ALLOW_USER_RECHARGE: bool = False

    # 用户自助注册开关：默认关闭，开启后登录页显示注册入口
    DEFAULT_ALLOW_REGISTER: bool = False

    # 初始管理员（首次启动自动创建，请尽快改密码）
    INIT_ADMIN_USERNAME: str = "admin"
    INIT_ADMIN_PASSWORD: str = "admin123"

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
