#!/bin/bash

# サーバーの環境構築（make setup の本体）。ツールのインストール・ディレクトリ準備・
# gitまわりのセットアップを行う。

set -euo pipefail
cd "$(dirname "$0")/.."

scripts/install-tools.sh

# ディレクトリ準備
mkdir -p tool-config/alp tool-config/slow-query tool-config/nginx

# サーバー上のgit identity。ここで作られるコミットはs1の「配布コード取り込み」だけなので
# 厳密である必要はない。既に設定済みなら尊重し、未設定のときだけ中立な値を入れる。
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "isucon"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "isucon@localhost"

git add .
git commit -m "chore: setup"
git push origin main
