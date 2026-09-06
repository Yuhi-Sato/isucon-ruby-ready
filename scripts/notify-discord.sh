#!/bin/bash

# alp / slow-query の集計結果をDiscordに通知する（make notify-discord-alp 等の本体）。
# 引数（alp / slow-query）が scripts/ のスクリプト名を兼ねる。
# Webhook URLはsecrets.env経由で渡す（README「secrets.envの配布」参照）。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

TARGET="${1:-}"
echo "$TARGET" | grep -qE '^(alp|slow-query)$' || { echo "unknown notify target: ${TARGET} (expected alp / slow-query)" >&2; exit 1; }

TARGET_UPPER=$(echo "$TARGET" | tr 'a-z-' 'A-Z_')
webhook_var="DISCORD_WEBHOOK_URL_${TARGET_UPPER}"
username_var="DISCORD_USERNAME_${TARGET_UPPER}"
webhook_url="${!webhook_var:-${DISCORD_WEBHOOK_URL:-}}"
username="${!username_var:-$TARGET}"

if [ -z "$webhook_url" ]; then
  echo "set ${webhook_var} (or common DISCORD_WEBHOOK_URL) in secrets.env" >&2
  echo "  see README: secrets.envの配布" >&2
  exit 1
fi

rm -f "$NOTIFY_DISCORD_TMPFILE"
mkdir -p tmp
"scripts/${TARGET}.sh" > "$NOTIFY_DISCORD_TMPFILE"

stamp=$(date "+%Y-%m-%d-%H:%M:%S")
filename="${stamp}-${TARGET}.txt"
payload=$(printf '{"username":"%s","content":"%s"}' "$username" "$filename")

curl --fail --silent --show-error --max-time 30 \
  -F "payload_json=${payload}" \
  -F "files[0]=@${NOTIFY_DISCORD_TMPFILE};filename=${filename};type=text/plain" \
  "$webhook_url" >/dev/null

echo "notified ${TARGET} to Discord"
