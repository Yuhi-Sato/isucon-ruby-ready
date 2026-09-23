#!/bin/bash

# nginxアクセスログ（ltsv）をalpで集計する（make alp の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

measure_log_meta
log_file=$(measure_log_path alp)
{ measure_log_header; sudo alp ltsv --file="$NGINX_LOG" --config=tool-config/alp/config.yml; } | tee "$log_file"
echo "saved: $log_file" >&2
scripts/push-measure-log.sh "$log_file"
