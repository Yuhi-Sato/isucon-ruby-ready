#!/bin/bash

# nginxアクセスログ（ltsv）をalpで集計する（make alp の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

log_file=$(measure_log_path alp)
sudo alp ltsv --file="$NGINX_LOG" --config=tool-config/alp/config.yml | tee "$log_file"
echo "saved: $log_file" >&2
