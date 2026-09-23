#!/bin/bash

# ローカルに回収した measure-logs/ だけをcommitする（pushはしない）。
# scripts/fetch-measure-logs.sh から呼ばれる。-all系ターゲットでは並列回収がgitのindex.lockで
# ぶつからないよう、回収後に Makefile から一度だけ呼ぶ。
# パス指定の git commit なので、作業中の他の変更（staged含む）は巻き込まない。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

[ -d "$MEASURE_LOG_DIR" ] || exit 0
git add -- "$MEASURE_LOG_DIR"
if git diff --cached --quiet -- "$MEASURE_LOG_DIR"; then
  exit 0
fi

# measure-logs/<SERVER_ID>/... からサーバー名を拾ってメッセージに入れる
servers=$(git diff --cached --name-only -- "$MEASURE_LOG_DIR" | cut -d/ -f2 | sort -u | paste -sd, -)
git commit --quiet -m "計測ログを記録 (${servers})" -- "$MEASURE_LOG_DIR"
echo "committed: $(git log -1 --format='%h %s')（pushは手動で）"
