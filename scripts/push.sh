#!/bin/sh
# 一键推送：sh scripts/push.sh https://github.com/<你>/<repo>.git <PAT>
# PAT 也可不传，走 SSH 或已有凭证
set -eu
URL=${1:?用法: sh scripts/push.sh <仓库地址> [PAT]}
PAT=${2:-}
cd "$(dirname "$0")/.."

if [ -n "$PAT" ]; then
  # 尽量不把 token 写进 .git/config
  PUSH_URL=$(printf '%s' "$URL" | sed -E "s#https://#https://${PAT}@#")
else
  PUSH_URL=$URL
fi

git remote remove origin 2>/dev/null || true
git remote add origin "$URL"
git branch -M main 2>/dev/null || true
echo "== 推送"
git push -u "$PUSH_URL" HEAD:main --force-with-lease 2>/dev/null || git push -u "$PUSH_URL" HEAD:main
echo "== 完成"
