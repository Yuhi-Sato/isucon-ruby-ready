#!/bin/bash

# 解析ツール（alp等）のインストール（setup.shから呼び出される）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo apt-get update

# NEEDRESTART_MODE=a / DEBIAN_FRONTEND=noninteractive:
# Ubuntu 22.04+ は apt install 中に needrestart の対話ダイアログが出て止まることがあるため無効化する
# unzip/wget: alpのzip展開とダウンロード用
# curl: Discord Webhook通知（make nd）用
# dstat: CPU/iowait 確認用（スキルから参照）
sudo NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get install -y \
  unzip wget curl dstat

# アーカイブの展開はtmpディレクトリで行う。リポジトリルートで展開すると
# 同梱のREADME.md等がリポジトリのファイルを上書きしてしまうため
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"

# alpのインストール（releases/latest/download は常に最新リリースを指す）
wget "https://github.com/tkuchiki/alp/releases/latest/download/alp_linux_${ARCH}.zip"
unzip "alp_linux_${ARCH}.zip"
sudo install alp /usr/local/bin/alp
