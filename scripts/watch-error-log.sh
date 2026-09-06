#!/bin/bash

# nginx/MySQLのエラーログを追尾する（make watch-error-log の本体）。
# アプリ側のエラーはjournalctl経由なので watch-service-log を使う。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo tail -n 10 -F "$NGINX_ERROR_LOG" "$DB_ERROR_LOG"
