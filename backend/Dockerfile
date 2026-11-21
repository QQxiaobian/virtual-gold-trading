FROM python:3.11-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai

# build context 为项目根目录（见 docker-compose.yml）
COPY backend/requirements.txt ./requirements.txt
# 使用国内镜像源加速构建（NAS 上同样受益）
RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt

# 后端代码
COPY backend/app/ ./app/

# Flutter Web 静态产物：由 FastAPI 直接托管，与 API 共用同一容器、同一端口。
# 这样不依赖 nginx 容器 / 相对路径挂载，避免 NAS 图形界面部署时 403。
COPY app/build/web/ ./web/

# 版本号文件（config.py 读取，避免显示写死的旧版本）
COPY VERSION ./VERSION

# 数据目录（挂载卷持久化）
RUN mkdir -p /app/data

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
