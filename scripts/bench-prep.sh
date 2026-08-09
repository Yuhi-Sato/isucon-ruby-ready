#!/bin/bash

# ベンチマーク直前に実行する（make bench-prep の本体）。
# ログ削除・設定反映・DB/nginx含む全再起動を伴う。
# git pull 後にリポジトリ内の他スクリプトを呼ぶため、それらは常にpull済みの最新版で実行される。

set -euo pipefail
cd "$(dirname "$0")/.."

git pull

. scripts/vars.sh
scripts/check-server-id.sh
(cd "$APP_DIR" && bundle install)
scripts/rm-logs.sh
scripts/deploy-conf.sh
scripts/restart.sh all
