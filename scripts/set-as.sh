#!/bin/bash

# このサーバーをs1/s2/s3として設定する（make set-as-s1 等の本体）。
# 既存の SERVER_ID 行を消してから追記するので、再実行や役割変更（s1→s2）でも重複しない。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

ROLE="${1:-}"
echo "$ROLE" | grep -qE '^s[1-3]$' || { echo "invalid server id: ${ROLE} (expected s1 / s2 / s3)" >&2; exit 1; }

mkdir -p "${ROLE}${DB_PATH}" "${ROLE}${NGINX_PATH}"

# 配布環境に無い練習用AMI等でも通るよう、無ければ空ファイルを作る
[ -f "$HOME/env.sh" ] || touch "$HOME/env.sh"

cp "$HOME/env.sh" "${ROLE}/env.sh"
sed -i '/^SERVER_ID=/d' "${ROLE}/env.sh" "$HOME/env.sh"
printf '\nSERVER_ID=%s\n' "$ROLE" >> "${ROLE}/env.sh"
printf '\nSERVER_ID=%s\n' "$ROLE" >> "$HOME/env.sh"

