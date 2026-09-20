#!/bin/bash

# SERVER_ID（env.sh内で定義。make set-as-s1 等で設定される）の存在チェック。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

if [ -n "${SERVER_ID:-}" ]; then
  echo "SERVER_ID=${SERVER_ID}"
else
  echo "SERVER_ID is unset" >&2
  exit 1
fi
