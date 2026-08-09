#!/bin/bash

# アプリの*.rbからSQLクエリを抽出してqueries/以下に出力する（make extract-sql 等の本体）。
# 一行のクォート文字列クエリと、ヒアドキュメント（<<~SQL 等）で書かれたクエリの両方を抽出する。
# 引数: select / insert / update / delete / all（省略時はall）

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

extract() {
  keyword="$1"
  kw="$(echo "$keyword" | tr a-z A-Z)"
  out="queries/${keyword}.sql"

  # shellcheck disable=SC2038  # ISUCONアプリの.rbパスに空白・特殊文字は想定しない
  # grepは1件もマッチしないと非0で終了するが、クエリ0件は正常ケースなので握りつぶす
  find "$APP_DIR" -name "*.rb" | xargs -r grep -h -oE "\"${kw}[^\"]*\"|'${kw}[^']*'" | sed -E "s/^[\"']//; s/[\"']\$//" > "$out" || true
  echo >> "$out"
  echo "----------------------------------------- heredoc queries -----------------------------------------" >> "$out"
  # shellcheck disable=SC2038
  find "$APP_DIR" -name "*.rb" | xargs -r awk -v kw="$kw" '/<<[-~]?SQL/ { capture=1; buf=""; next } capture && /^[[:space:]]*SQL[[:space:]]*$/ { capture=0; if (buf ~ kw) printf "%s", buf; next } capture { buf = buf $0 "\n" }' >> "$out"
}

mkdir -p queries

if [ "$#" -eq 0 ] || [ "$1" = "all" ]; then
  set -- select insert update delete
fi

for keyword in "$@"; do
  echo "$keyword" | grep -qE '^(select|insert|update|delete)$' || { echo "unknown keyword: ${keyword} (expected select / insert / update / delete)" >&2; exit 1; }
  extract "$keyword"
done
