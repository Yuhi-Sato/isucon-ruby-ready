#!/bin/bash

# 直近のVernierプロファイル（Markdown形式）を表示する（make vernier-view の本体）。
# tmp/vernier以下に出力されている想定。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

latest="$(ls -t "$APP_DIR"/tmp/vernier/*.md 2>/dev/null | head -n 1 || true)"
[ -n "$latest" ] || { echo "no profile found in ${APP_DIR}/tmp/vernier" >&2; exit 1; }
cat "$latest"
