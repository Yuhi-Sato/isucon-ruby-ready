#!/bin/bash

# 軽量デプロイの本体（make deploy / remote-deploy が git pull 後に呼ぶ）。
# bundle install からデーモン再起動（daemon-reload + アプリ再起動）まで行う。
# ログは消さない・DB/nginxは再起動しない（全再起動を伴うベンチ準備は scripts/bench-prep.sh）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

scripts/check-server-id.sh
(cd "$APP_DIR" && bundle install)
scripts/restart.sh app
