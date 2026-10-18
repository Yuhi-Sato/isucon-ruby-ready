#!/bin/bash

# topをバックグラウンドで一定時間サンプリングして保存する（make top の本体）。
# ベンチ走行中に並行して実行する想定のため、alp/slow-queryと違いベンチ後ではなく走行中に叩く。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

TOP_DURATION="${TOP_DURATION:-2}"
TOP_INTERVAL="${TOP_INTERVAL:-20}"
TOP_DELAY="${TOP_DELAY:-0}"

sleep "$TOP_DELAY"
measure_log_meta
log_file=$(measure_log_path top)
{ measure_log_header; top -bn "$TOP_DURATION" -d "$TOP_INTERVAL"; } | tee "$log_file"
echo "saved: $log_file" >&2
scripts/push-measure-log.sh "$log_file"
