#!/usr/bin/env bash
# 打包 NAS 部署包：仅包含 Docker 部署所需文件，排除虚拟环境、数据库、git。
# 单容器方案：后端镜像内已包含 Flutter Web 静态文件，无需独立 nginx 容器。
# 用法：bash scripts/package_nas.sh [输出目录]
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTDIR="${1:-$ROOT/releases}"
VERSION="$(cat VERSION | tr -d '[:space:]')"
NAME="virtual-gold-trading-nas-v${VERSION}"
TMP="$(mktemp -d)"
PKG="$TMP/$NAME"

mkdir -p "$PKG/backend" "$PKG/app/build" "$OUTDIR"

# 后端运行所需（排除 .venv / data / __pycache__）
cp -r backend/app "$PKG/backend/"
cp backend/Dockerfile backend/requirements.txt backend/.env.example "$PKG/backend/"
# VERSION 放在包根：Dockerfile 中 COPY VERSION 使用项目根作为上下文
cp VERSION "$PKG/VERSION"
find "$PKG/backend" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# Web 前端构建产物（后端 Dockerfile 会 COPY app/build/web/ 进镜像）
cp -r app/build/web "$PKG/app/build/web"

# Docker 与文档
cp docker-compose.yml .env.example README.md CHANGELOG.md VERSION LICENSE "$PKG/"

# 简洁的 NAS 部署说明
cat > "$PKG/部署说明.txt" << EOF
虚拟黄金交易系统 NAS 部署包 v${VERSION}
============================================

一、快速部署（单容器，最简单）
  1. 把本目录整个上传到 NAS 的某个文件夹（如 /docker/gold）
  2. cd 进入该目录
  3. cp .env.example .env  然后编辑 .env，务必修改 SECRET_KEY 和管理员密码
  4. docker compose up -d --build
  5. 验证：
     - 网页端：  http://<NAS_IP>:8101
     - 后端 API：http://<NAS_IP>:8100/docs

二、重要：删除旧的双容器（如之前部署过 v1.1.4 及更早）
  Web 已改为由后端直接托管，不再需要 gold-web 容器。
  部署前请在 Docker 面板删除旧的 gold-web 容器和 gold-web:local 镜像，
  否则旧的 8101 端口映射会冲突。本包只需一个 gold-backend 容器。

三、端口说明
  - 8100：后端 API + APP 访问（docker-compose 中 "8100:8000"）
  - 8101：Web 页面（同一后端服务，"8101:8000"）
  两个端口指向同一个容器，改端口请编辑 docker-compose.yml 的 ports。

四、数据持久化与备份
  数据库在 backend/data/ 目录，定期备份该目录即可。重新部署不会丢数据。

五、客户端
  - 网页端：浏览器打开 http://<NAS_IP>:8101
  - Android：安装同版本 Release 附带的 APK，登录页点「服务器」填 http://<NAS_IP>:8100

六、安全
  默认管理员 admin / admin123，登录后请立即修改。
EOF

tar -czf "$OUTDIR/${NAME}.tar.gz" -C "$TMP" "$NAME"
rm -rf "$TMP"

echo "打包完成：$OUTDIR/${NAME}.tar.gz"
ls -lh "$OUTDIR/${NAME}.tar.gz"
