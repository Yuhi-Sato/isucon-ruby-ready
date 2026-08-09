#!/bin/bash

# サーバーの環境構築（make setup の本体）。ツールのインストール・ディレクトリ準備・
# gitまわりのセットアップを行う。
# 注意: リポジトリルートの setup.sh（ローカル実行専用のオーケストレーター）とは別物。

set -euo pipefail
cd "$(dirname "$0")/.."

scripts/install-tools.sh

# ディレクトリ準備
mkdir -p tool-config/alp tool-config/slow-query tool-config/nginx queries
touch queries/.keep

# git用の設定は適宜変更して良い
git config --global user.email "yuhi120101@gmail.com"
git config --global user.name "Yuhi-Sato"
