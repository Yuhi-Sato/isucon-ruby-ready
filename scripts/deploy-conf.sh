#!/bin/bash

# git管理下（s1/等）のDB/nginx設定・env.shをサーバーに反映する（make deploy-conf の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

scripts/check-server-id.sh

sudo cp -R "${SERVER_ID}${DB_PATH}"/* "${DB_PATH}"
sudo cp -R "${SERVER_ID}${NGINX_PATH}"/* "${NGINX_PATH}"
cp "${SERVER_ID}/env.sh" "$HOME/env.sh"
