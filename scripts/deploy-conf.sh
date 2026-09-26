#!/bin/bash

# git管理下（s1/等）のDB/nginx設定・アプリのsystemdユニット・env.shをサーバーに反映する。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

scripts/check-server-id.sh

sudo cp -R "${SERVER_ID}${DB_PATH}"/* "${DB_PATH}"
sudo cp -R "${SERVER_ID}${NGINX_PATH}"/* "${NGINX_PATH}"
# ユニット変更の反映に必要な daemon-reload は restart.sh が行う。
# get-conf がユニットを取り込む前にsetupした sN/ には無いので、あるときだけ反映する
if [ -d "${SERVER_ID}${SYSTEMD_PATH}" ]; then
  sudo cp -R "${SERVER_ID}${SYSTEMD_PATH}"/* "${SYSTEMD_PATH}"
fi
cp "${SERVER_ID}/env.sh" "$HOME/env.sh"
