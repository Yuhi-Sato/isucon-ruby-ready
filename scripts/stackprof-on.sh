#!/bin/bash

# アプリのCPUプロファイリングを有効にして再起動する（make stackprof-on の本体）。
# systemdのdrop-inで RUBYOPT に tool-config/stackprof/boot.rb を載せる。アプリのコードは変えない。
# 止めるときは scripts/stackprof-report.sh（drop-inを消して再起動し、dumpを集計する）。
# プロファイル中はオーバーヘッドがあるため、このあいだのベンチのスコアは評価に使わない。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

scripts/check-server-id.sh
command -v stackprof >/dev/null || { echo "stackprof 未導入です。先に make install-stackprof を実行してください" >&2; exit 1; }

REPO_DIR=$(pwd)
OUT_DIR="${REPO_DIR}/tmp/stackprof"
DROPIN_DIR="${SYSTEMD_PATH}/${SERVICE_NAME}.service.d"

# 前回の取り残しが混ざらないよう、未処理のdumpを消す（処理済みは done/ にある）
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.dump

sudo mkdir -p "$DROPIN_DIR"
sudo tee "${DROPIN_DIR}/zz-stackprof.conf" >/dev/null <<CONF
[Service]
Environment=RUBYOPT=-r${REPO_DIR}/tool-config/stackprof/boot.rb
Environment=STACKPROF_OUT_DIR=${OUT_DIR}
CONF

scripts/restart.sh app
echo "stackprof ON: ${SERVICE_NAME}。ベンチ後に make stackprof-report で集計する" >&2
