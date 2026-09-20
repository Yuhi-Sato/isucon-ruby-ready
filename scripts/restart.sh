#!/bin/bash

# デーモンの再起動（make restart / make restart-app の本体）。
#   all: DB→アプリ→nginxの順に全再起動する。アプリを先にするとDB再起動中に起動して
#        接続確立に失敗する可能性がある（起動時にコネクションを張る実装の場合）
#   app: アプリのみ再起動する（軽量デプロイ用。DB/nginxは触らない）
# どちらも先に daemon-reload を行うので、systemdユニットの変更も反映される。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

MODE="${1:-all}"
case "$MODE" in
  all|app) ;;
  *) echo "Usage: $0 [all|app]" >&2; exit 1 ;;
esac

sudo systemctl daemon-reload
[ "$MODE" != "all" ] || sudo systemctl restart "$DB_SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"
[ "$MODE" != "all" ] || sudo systemctl restart nginx
