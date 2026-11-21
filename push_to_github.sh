#!/usr/bin/env bash
# 将本项目推送到 GitHub 私有仓库（首次运行会创建仓库）
# 用法：
#   1. 先确保已登录 GitHub：gh auth login
#   2. 修改下方 REPO_NAME（可选）
#   3. bash push_to_github.sh
set -e

REPO_NAME="${1:-virtual-gold-trading}"
GH_USER="${GH_USER:-$(gh api user -q .login 2>/dev/null || echo '')}"

if [ -z "$GH_USER" ]; then
  echo "错误：未登录 GitHub，请先运行 gh auth login"
  exit 1
fi

cd "$(dirname "$0")"

echo "当前 GitHub 用户：$GH_USER"
echo "目标仓库：$GH_USER/$REPO_NAME (Private)"

# 若远端不存在则创建私有仓库
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "创建私有仓库..."
  gh repo create "$REPO_NAME" --private --source=. --remote=origin --push
else
  echo "推送到已有远端 origin..."
  git push -u origin main
fi

echo "完成！仓库地址：https://github.com/$GH_USER/$REPO_NAME"
