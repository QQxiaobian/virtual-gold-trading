#!/usr/bin/env bash
# 发版脚本：升版本号 → 打 tag → 推送 → 由 GitHub Actions 自动构建 NAS 包+APK 并创建 Release。
#
# 用法：
#   bash scripts/release.sh 1.1.0 "本次更新说明"
# 若不传版本号，则按 VERSION 当前值打 tag。
#
# 前置：gh auth login（有 repo 权限）；本地 git 工作区干净。
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NEW_VERSION="$1"
CHANGE_NOTE="${2:-}"
CURRENT="$(cat VERSION | tr -d '[:space:]')"

if [ -n "$NEW_VERSION" ]; then
  # 更新 VERSION、CHANGELOG、前端版本号常量
  echo "$NEW_VERSION" > VERSION
  python3 - "$NEW_VERSION" "$CHANGE_NOTE" << 'PY'
import sys, re, datetime
new, note = sys.argv[1], sys.argv[2]
p = "CHANGELOG.md"
s = open(p, encoding="utf-8").read()
entry = f"## [{new}] - {datetime.date.today().isoformat()}\n\n{note or '常规更新。'}\n\n"
s = re.sub(r"(## \[[^\]]+\] - \d{4}-\d{2}-\d{2})", entry + r"\1", s, count=1)
open(p, "w", encoding="utf-8").write(s)

# 前端 API 里的版本常量
api = "app/lib/services/api.dart"
a = open(api, encoding="utf-8").read()
a = re.sub(r'static const String version = "[^"]+";', f'static const String version = "{new}";', a)
open(api, "w", encoding="utf-8").write(a)
PY
  git add -A
  git commit -m "chore: 升级版本至 $NEW_VERSION"
fi

TAG="v${NEW_VERSION:-$CURRENT}"
echo "打标签 $TAG ..."
git tag -a "$TAG" -m "Release $TAG" 2>/dev/null || echo "标签已存在，跳过"

echo "推送代码与标签（GitHub Actions 将自动构建并发布 Release）..."
git push origin HEAD
git push origin "$TAG"

echo "完成！稍后查看 Release：https://github.com/$(gh api user -q .login)/$(basename "$ROOT")/releases/tag/$TAG"
