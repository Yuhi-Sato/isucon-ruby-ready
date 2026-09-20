#!/bin/bash

# サーバーの環境構築（make setup-s1 等の本体）。ツールのインストール・ディレクトリ準備・
# SERVER_ID（s1/s2/s3）の設定・gitまわりのセットアップを行う。

set -euo pipefail
cd "$(dirname "$0")/.."

ROLE="${1:-}"
echo "$ROLE" | grep -qE '^s[1-3]$' || { echo "usage: $0 s1|s2|s3" >&2; exit 1; }

scripts/install-tools.sh

# ディレクトリ準備
mkdir -p tool-config/alp tool-config/slow-query tool-config/nginx

# SERVER_ID をセット（get-conf / deploy-conf の前提）。commit 前に走らせて sN/ を初回pushに含める
scripts/set-as.sh "$ROLE"

# 実際のDB/nginx設定・env.shを sN/ 配下に取り込む（初回commitからgit管理下に置く）
scripts/get-conf.sh

# サーバー上のgit identity。ここで作られるコミットはs1の「配布コード取り込み」だけなので
# 厳密である必要はない。既に設定済みなら尊重し、未設定のときだけ中立な値を入れる。
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "isucon"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "isucon@localhost"

git add .
git commit -m "chore: setup (${ROLE})"
git push origin main
