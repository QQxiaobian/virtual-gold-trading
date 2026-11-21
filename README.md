# 虚拟黄金交易系统

自用的虚拟黄金交易系统：多用户账号、虚拟资金、黄金买卖、实时金价与走势图、手续费管理、后台管理。前端 Flutter 一套代码编译 **Android APK + Web**，后端 FastAPI 部署在 NAS Docker 中。

> 模拟盘：资金与行情仅用于个人记账娱乐，不构成真实投资建议。

## 功能

- 账号管理：注册/登录、JWT 鉴权、普通用户/管理员角色
- 资金管理：虚拟充值、资金流水、后台资金调整
- 买卖交易：按实时金价买入/卖出克数，手续费双模式（百分比/每克固定），成本均价含手续费，收益计算
- 行情：新浪上金所 Au99.99 实时金价（元/克），多时间维度走势图
- 后台管理：用户管理、费率配置、全局流水、手续费统计
- 界面参考图风格：持仓卡片、收益三栏、涨跌幅曲线、底部导航（涨红跌绿）

## 快速开始

### 1. 后端（本地开发）

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env      # 修改 SECRET_KEY 和管理员密码
uvicorn app.main:app --reload --port 8000
```

访问 http://localhost:8000/docs 查看 API 文档。首次启动自动创建管理员（默认 `admin / admin123`，请尽快修改）。

### 2. 后端（NAS Docker 部署）⭐

```bash
cp .env.example .env      # 务必修改 SECRET_KEY 与管理员密码
docker compose up -d --build
```

- 服务地址：`http://<NAS_IP>:8100`（默认端口 8100，可在 `docker-compose.yml` 中修改映射）
- 数据库持久化在 `backend/data/`，记得备份该目录
- 外网访问建议用 Tailscale/ZeroTier 或反向代理，不要直接暴露公网
- 修改 `.env` 后需 `docker compose up -d --build` 重建

### 3. 前端（Flutter）

```bash
cd app
flutter pub get
# Web（已在本项目验证构建成功）
flutter build web --release
# Android APK（需要 Android SDK）
flutter build apk --release
```

**APK 产物**：`app/build/app/outputs/flutter-apk/app-release.apk`
**Web 产物**：`app/build/web/`（已构建好，可直接部署到 NAS 静态服务器）

> **现成 APK**：每个版本的 Release 页面都附带已编译好的 `虚拟黄金交易-vX.Y.Z.apk`，可直接下载安装，无需自己编译。
>
> **自行编译**（可选）：需要 Android SDK。在你的电脑或 NAS 上安装 Android Studio（首次启动会自动装 SDK），或安装命令行工具：
> `sdkmanager "platform-tools" "platforms;android-31" "build-tools;31.0.0"`，
> 然后设置 `ANDROID_SDK_ROOT` 环境变量，再执行 `flutter build apk --release`。
> 注意：Gradle 7.4 需配合 JDK 17（不兼容 JDK 20+）。Flutter 版本要求：本代码基于 Flutter 3.0.0 / Dart 2.17，依赖已锁定兼容版本。

**修改 API 地址**（两种方式）：
1. App 内：登录后进入「我的 → 服务器设置」，填入 NAS 地址（如 `http://192.168.1.10:8100`），保存后重新登录
2. 代码默认：编辑 `app/lib/services/api.dart` 中的 `baseUrl`

## 测试

```bash
cd backend && .venv/bin/python ../tests/test_core.py
```

## 版本号规则

| 类型 | 规则 | 示例 |
|---|---|---|
| 初始 | 固定 | 1.0.0 |
| 小更新 | 第三段 +1 | 1.0.0 → 1.0.1 |
| 大更新 | 第二段 +1，第三段归零 | 1.0.1 → 1.1.0 |

每次更新：改 `VERSION` 文件、后端 `config.py` 的 `VERSION`、前端 `api.dart` 的 version、写 `CHANGELOG.md`、Git 打 tag `vX.Y.Z`。

## 目录结构

```
virtual-gold-trading/
├── backend/          FastAPI 后端
│   ├── app/
│   │   ├── models.py           数据模型
│   │   ├── schemas.py          Pydantic 模型
│   │   ├── auth.py             JWT 鉴权
│   │   ├── routers/            API 路由
│   │   └── services/           交易/金价/配置/定时任务
│   ├── Dockerfile
│   └── requirements.txt
├── app/              Flutter 前端（Android + Web）
├── tests/            核心逻辑测试
├── docker-compose.yml
└── .github/workflows/ci.yml
```

## 安全提醒

1. 部署前务必修改 `SECRET_KEY` 和 `INIT_ADMIN_PASSWORD`
2. 登录后第一时间修改管理员密码
3. `.env` 和数据库文件不要提交到 Git（已在 .gitignore 中）
