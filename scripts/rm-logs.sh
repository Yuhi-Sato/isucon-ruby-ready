#!/bin/bash

# アクセスログ・スロークエリログ・クエリダイジェスト統計を空にする（make rm-logs の本体）。
# rm ではなく truncate を使う: rm だと書き込み中のプロセスが削除済みinodeに
# 書き続けて新しいログが取れない。truncate ならプロセス再起動なしでログを空にできる。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

sudo test ! -f "$NGINX_LOG" || sudo truncate -s 0 "$NGINX_LOG"

# /var/log/mysql はisuconユーザーから読めない(750 mysql:adm)ため、存在確認もsudoで行う
sudo test ! -f "$DB_SLOW_LOG" || sudo truncate -s 0 "$DB_SLOW_LOG"

# MySQL停止中でもrm-logs全体は失敗させない
sudo mysql -e "TRUNCATE performance_schema.events_statements_summary_by_digest" 2>/dev/null || true
