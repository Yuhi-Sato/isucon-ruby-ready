#!/bin/bash

# alp / slow-query の集計結果をSlackに通知する（make notify-slack-alp 等の本体）。
# 引数（alp / slow-query）が scripts/ のスクリプト名と tool-config/ のディレクトリ名を兼ねる。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

TARGET="${1:-}"
echo "$TARGET" | grep -qE '^(alp|slow-query)$' || { echo "unknown notify target: ${TARGET} (expected alp / slow-query)" >&2; exit 1; }

rm -f "$NOTIFY_SLACK_TMPFILE"
mkdir -p tmp
"scripts/${TARGET}.sh" > "$NOTIFY_SLACK_TMPFILE"
notify_slack -c "tool-config/${TARGET}/notify-slack.toml" -snippet -filename="$(date "+%Y-%m-%d-%H:%M:%S").txt" < "$NOTIFY_SLACK_TMPFILE"
