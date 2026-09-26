#!/bin/bash

# サーバーの実際のDB/nginx設定・アプリのsystemdユニット・env.shをgit管理下（s1/等）にコピーする（setup.shから呼び出される）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

scripts/check-server-id.sh

mkdir -p "${SERVER_ID}${DB_PATH}" "${SERVER_ID}${NGINX_PATH}"

sudo cp -R "${DB_PATH}"/* "${SERVER_ID}${DB_PATH}"
sudo chown -R "$ISUCON_USER" "${SERVER_ID}${DB_PATH}"

sudo cp -R "${NGINX_PATH}"/* "${SERVER_ID}${NGINX_PATH}"
sudo chown -R "$ISUCON_USER" "${SERVER_ID}${NGINX_PATH}"

# 配布時のユニット実体は /lib/systemd/system 側やシンボリックリンクのこともあるため FragmentPath で探して実体をコピーする。
# 取り込み先は常に sN/etc/systemd/system にし、deploy-conf で /etc/systemd/system に置いて優先させる
UNIT_SRC=$(systemctl show -p FragmentPath --value "${SERVICE_NAME}.service")
if [ -n "$UNIT_SRC" ]; then
  mkdir -p "${SERVER_ID}${SYSTEMD_PATH}"
  sudo cp -L "$UNIT_SRC" "${SERVER_ID}${SYSTEMD_PATH}/${SERVICE_NAME}.service"
  # drop-in（systemctl edit で作られる override.conf 等）があれば一緒に取り込む
  if [ -d "${SYSTEMD_PATH}/${SERVICE_NAME}.service.d" ]; then
    sudo cp -RL "${SYSTEMD_PATH}/${SERVICE_NAME}.service.d" "${SERVER_ID}${SYSTEMD_PATH}/"
  fi
  sudo chown -R "$ISUCON_USER" "${SERVER_ID}${SYSTEMD_PATH}"
else
  echo "warning: ${SERVICE_NAME}.service が見つからないため systemd ユニットは取り込まない（scripts/vars.sh の SERVICE_NAME を確認）" >&2
fi

cp "$HOME/env.sh" "${SERVER_ID}/env.sh"
