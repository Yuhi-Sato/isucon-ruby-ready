#!/bin/bash

# systemd/nginx/MySQLのエラーログの現在地・設定を確認する（make check-error-log-config の本体）。
# 推測でscripts/vars.shのNGINX_ERROR_LOG/DB_ERROR_LOGを決め打ちしないよう、
# 実サーバーの実際の設定をここでまとめて確認する（error-log-setup.md参照）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

echo "## systemd (${SERVICE_NAME}) の標準出力/エラー設定"
systemctl cat "$SERVICE_NAME" | grep -i '^standard' || echo "(StandardOutput/StandardError未設定 = デフォルトのjournalに出力される)"

echo
echo "## nginx の error_log 設定"
sudo nginx -T 2>/dev/null | grep error_log

echo
echo "## MySQL の log_error 設定"
sudo mysql -e "SHOW VARIABLES LIKE 'log_error%'"

echo
echo "## scripts/vars.sh との突き合わせ"
echo "NGINX_ERROR_LOG=${NGINX_ERROR_LOG}"
echo "DB_ERROR_LOG=${DB_ERROR_LOG}"
echo "(上記の実際の設定と一致しない場合はscripts/vars.shを実サーバーに合わせて修正する)"
