#!/bin/bash

# alp / slow-query の集計結果をDiscordに通知する（make notify-discord-alp 等の本体）。
# 引数（alp / slow-query）が scripts/ のスクリプト名と tool-config/ のディレクトリ名を兼ねる。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

TARGET="${1:-}"
echo "$TARGET" | grep -qE '^(alp|slow-query)$' || { echo "unknown notify target: ${TARGET} (expected alp / slow-query)" >&2; exit 1; }

CONFIG="tool-config/${TARGET}/notify-discord.toml"
if [ ! -f "$CONFIG" ]; then
  echo "missing ${CONFIG}" >&2
  echo "  cp ${CONFIG}.example ${CONFIG}" >&2
  echo "then set webhook_url" >&2
  exit 1
fi

webhook_url=$(sed -nE 's/^webhook_url[[:space:]]*=[[:space:]]*"(.*)"[[:space:]]*$/\1/p' "$CONFIG" | tail -n1)
username=$(sed -nE 's/^username[[:space:]]*=[[:space:]]*"(.*)"[[:space:]]*$/\1/p' "$CONFIG" | tail -n1)
username="${username:-$TARGET}"

if [ -z "$webhook_url" ] || [ "$webhook_url" = "https://discord.com/api/webhooks/XXXX/XXXX" ]; then
  echo "set webhook_url in ${CONFIG}" >&2
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
