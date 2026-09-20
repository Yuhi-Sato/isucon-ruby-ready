#!/bin/bash

# サーバーの実際のDB/nginx設定・env.shをgit管理下（s1/等）にコピーする（make get-conf の本体）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

scripts/check-server-id.sh

mkdir -p "${SERVER_ID}${DB_PATH}" "${SERVER_ID}${NGINX_PATH}"

sudo cp -R "${DB_PATH}"/* "${SERVER_ID}${DB_PATH}"
sudo chown -R "$ISUCON_USER" "${SERVER_ID}${DB_PATH}"

sudo cp -R "${NGINX_PATH}"/* "${SERVER_ID}${NGINX_PATH}"
sudo chown -R "$ISUCON_USER" "${SERVER_ID}${NGINX_PATH}"

cp "$HOME/env.sh" "${SERVER_ID}/env.sh"
