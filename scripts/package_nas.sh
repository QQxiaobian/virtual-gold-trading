#!/usr/bin/env bash
# 打包 NAS 部署包：仅包含 Docker 部署后端所需文件，排除源码之外的构建产物、虚拟环境、数据库、git。
# 用法：bash scripts/package_nas.sh [输出目录]
# 产物：virtual-gold-trading-nas-v<VERSION>.tar.gz
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTDIR="${1:-$ROOT/releases}"
VERSION="$(cat VERSION | tr -d '[:space:]')"
NAME="virtual-gold-trading-nas-v${VERSION}"
TMP="$(mktemp -d)"
PKG="$TMP/$NAME"

mkdir -p "$PKG/backend" "$OUTDIR"

# 后端运行所需（排除 .venv / data / __pycache__）
cp -r backend/app "$PKG/backend/"
cp backend/Dockerfile backend/requirements.txt backend/.env.example "$PKG/backend/"
find "$PKG/backend" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# Web 前端（Flutter Web 构建产物 + nginx 反代配置 + 构建镜像用 Dockerfile）
mkdir -p "$PKG/web" "$PKG/app/build"
cp -r app/build/web "$PKG/app/build/web"
cp web/nginx.conf "$PKG/web/nginx.conf"
cp web/Dockerfile "$PKG/web/Dockerfile"

# Docker 与配置、文档
cp docker-compose.yml .env.example README.md CHANGELOG.md VERSION LICENSE "$PKG/"

# 附一份简洁的 NAS 部署说明
cat > "$PKG/部署说明.txt" << EOF
虚拟黄金交易系统 NAS 部署包 v${VERSION}
============================================

一、快速部署
  1. 把本目录整个上传到 NAS 的某个文件夹（如 /docker/gold）
  2. cd 进入该目录
  3. cp .env.example .env  然后编辑 .env，务必修改 SECRET_KEY 和管理员密码
  4. docker compose up -d --build
  5. 验证：
     - 后端 API：http://<NAS_IP>:8100/docs
     - 网页端：  http://<NAS_IP>:8101

二、默认端口
  - 后端 API：8100（docker-compose 中 "8100:8000"）
  - 网页 Web：8101（docker-compose 中 "8101:80"）
  如需修改，编辑 docker-compose.yml 的 ports 映射

三、数据持久化与备份
  数据库在 backend/data/ 目录，定期备份该目录即可

四、客户端
  - 网页端：浏览器打开 http://<NAS_IP>:8101（无需配置，Web 已内置反代 /api 到后端）
  - Android：安装同版本 Release 附带的 APK，首次进入在登录页点「服务器」填 http://<NAS_IP>:8100

五、安全
  默认管理员 admin / admin123，登录后请立即修改
EOF

# 打包（gzip）
tar -czf "$OUTDIR/${NAME}.tar.gz" -C "$TMP" "$NAME"
rm -rf "$TMP"

echo "打包完成：$OUTDIR/${NAME}.tar.gz"
ls -lh "$OUTDIR/${NAME}.tar.gz"
