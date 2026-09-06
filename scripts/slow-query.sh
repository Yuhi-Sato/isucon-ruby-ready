#!/bin/bash

# performance_schemaのクエリダイジェスト集計を表示する（make slow-query の本体）。
# N+1はcalls列で検出する。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

log_file=$(measure_log_path slow-query)
sudo mysql --table < tool-config/slow-query/ranking.sql | tee "$log_file"
echo "saved: $log_file" >&2
