#!/bin/bash

# 対象サーバー上の measure-logs/（make alp / make slow-query の保存先）をローカルへ回収する
# （scripts/remote.sh から remote-alp-* / remote-slow-query-* / remote-notify-discord-* / remote-nd の後に呼ばれる）。
# サーバー上でcommitするとサーバーのブランチがローカルと分岐し、次の git pull でコンフリクトしうる。
# そのためサーバーからは回収だけして元ファイルは消し、ローカルでcommitする（pushは手動）。
# worktreeごと消してログを失わないよう、回収したら即commitする。
# MEASURE_LOG_NO_COMMIT=1 のときはcommitしない（-all系で並列回収後にまとめてcommitするため）

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

# rsync は scripts/install-tools.sh で入れる。それ以前にセットアップしたサーバーには無いことがある
if ! ssh "$HOST" "command -v rsync >/dev/null"; then
  echo "rsync is not installed on ${HOST}: ssh ${HOST} sudo apt-get install -y rsync" >&2
  exit 1
fi

mkdir -p "$MEASURE_LOG_DIR"
# --remove-source-files: 転送できたファイルだけサーバー側から消す（未回収のログが残り続けないように）
fetched=$(rsync -a --remove-source-files --out-format="${MEASURE_LOG_DIR}/%n" \
  "${HOST}:$(printf %q "$remote_dir")/" "${MEASURE_LOG_DIR}/")
# ディレクトリ行（末尾/）と空行は除いてファイルだけ表示する
printf '%s\n' "$fetched" | grep -v -e '/$' -e '^$' | sed 's/^/fetched: /' || echo "no new measure logs on ${HOST}"

if [ "${MEASURE_LOG_NO_COMMIT:-}" != 1 ]; then
  scripts/commit-measure-logs.sh
fi
