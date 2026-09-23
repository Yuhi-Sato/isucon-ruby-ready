#!/bin/bash

# 対象サーバー上の measure-logs/（make alp / make slow-query の保存先）をローカルへ回収する
# （make remote-fetch-measure-logs-s1 等の本体。remote-notify-discord-* / remote-nd の後にも自動で呼ばれる）。
# サーバー上でcommitするとサーバーのブランチがローカルと分岐し、次の git pull でコンフリクトしうる。
# そのためサーバーからは回収だけして元ファイルは消し、commit・pushはローカルで行う。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

HOST="${1:-}"
REMOTE_DEPLOY_PATH="${REMOTE_DEPLOY_PATH:-/home/isucon}"

echo "$HOST" | grep -qE '^s[1-3]$' || {
  echo "usage: $0 s1|s2|s3" >&2
  exit 1
}

remote_dir="${REMOTE_DEPLOY_PATH}/${MEASURE_LOG_DIR}"
if ! ssh "$HOST" "test -d $(printf %q "$remote_dir")"; then
  echo "no measure logs on ${HOST}"
  exit 0
fi

mkdir -p "$MEASURE_LOG_DIR"
# --remove-source-files: 転送できたファイルだけサーバー側から消す（未回収のログが残り続けないように）
fetched=$(rsync -a --remove-source-files --out-format="${MEASURE_LOG_DIR}/%n" \
  "${HOST}:$(printf %q "$remote_dir")/" "${MEASURE_LOG_DIR}/")
# ディレクトリ行（末尾/）は除いてファイルだけ表示する
printf '%s\n' "$fetched" | grep -v '/$' | sed 's/^/fetched: /' || echo "no new measure logs on ${HOST}"
echo "次: git add ${MEASURE_LOG_DIR} && git commit -m '計測結果を記録'" >&2
