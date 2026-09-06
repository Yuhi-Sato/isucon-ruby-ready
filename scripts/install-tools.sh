#!/bin/bash

# 解析ツール（alp / DuckDB等）のインストール（make install-tools の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo apt-get update

# NEEDRESTART_MODE=a / DEBIAN_FRONTEND=noninteractive:
# Ubuntu 22.04+ は apt install 中に needrestart の対話ダイアログが出て止まることがあるため無効化する
# unzip/wget: alp・DuckDBのzip展開とダウンロード用
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

# DuckDB CLIのインストール（ユーザー行動履歴の分析用。isucon-user-behavior-analysis スキル参照）
wget "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-${ARCH}.zip"
unzip -o "duckdb_cli-linux-${ARCH}.zip"
sudo install duckdb /usr/local/bin/duckdb
