"""应用配置：全部可通过环境变量覆盖，便于 Docker 部署。"""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # 基础
    APP_NAME: str = "虚拟黄金交易系统"
    VERSION: str = "1.0.0"
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
