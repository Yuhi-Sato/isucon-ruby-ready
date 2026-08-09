#!/bin/bash

# ユーザー行動履歴の定型分析（make duckdb-flow 等の本体）。
# init.sql（LTSVアクセスログ→VIEW定義）を前置してtool-config/duckdb/のレシピを実行する。
# アクセスログの読み取りにroot権限が必要なためsudoで実行する。

set -euo pipefail
cd "$(dirname "$0")/.."

RECIPE="${1:-}"
[ -f "tool-config/duckdb/${RECIPE}.sql" ] || { echo "unknown recipe: ${RECIPE} (see tool-config/duckdb/)" >&2; exit 1; }

cat tool-config/duckdb/init.sql "tool-config/duckdb/${RECIPE}.sql" | sudo duckdb
