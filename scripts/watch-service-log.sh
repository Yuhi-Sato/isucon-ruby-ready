#!/bin/bash

# アプリのsystemdログを追尾する（make watch-service-log の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo journalctl -u "$SERVICE_NAME" -n10 -f
