#!/bin/bash

# 解析ツール（alp / notify_slack / DuckDB等）のインストール（make install-tools の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo apt-get update

# NEEDRESTART_MODE=a / DEBIAN_FRONTEND=noninteractive:
# Ubuntu 22.04+ は apt install 中に needrestart の対話ダイアログが出て止まることがあるため無効化する
sudo NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get install -y \
  percona-toolkit dstat git unzip snapd graphviz tree \
  build-essential libmysqlclient-dev libpq-dev zlib1g-dev libyaml-dev

# アーカイブの展開はtmpディレクトリで行う。リポジトリルートで展開すると
# 同梱のREADME.md等がリポジトリのファイルを上書きしてしまうため
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"

# alpのインストール（releases/latest/download は常に最新リリースを指す）
wget "https://github.com/tkuchiki/alp/releases/latest/download/alp_linux_${ARCH}.zip"
unzip "alp_linux_${ARCH}.zip"
sudo install alp /usr/local/bin/alp

# notify_slackのインストール（releases/latest/download は常に最新リリースを指す）
wget "https://github.com/catatsuy/notify_slack/releases/latest/download/notify_slack-linux-${ARCH}.tar.gz"
tar -xvf "notify_slack-linux-${ARCH}.tar.gz"
sudo install notify_slack /usr/local/bin/notify_slack

# DuckDB CLIのインストール（ユーザー行動履歴の分析用。isucon-user-behavior-analysis スキル参照）
wget "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-${ARCH}.zip"
unzip -o "duckdb_cli-linux-${ARCH}.zip"
sudo install duckdb /usr/local/bin/duckdb
