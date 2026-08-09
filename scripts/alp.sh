#!/bin/bash

# nginxアクセスログ（ltsv）をalpで集計する（make alp の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo alp ltsv --file="$NGINX_LOG" --config=tool-config/alp/config.yml
