#!/bin/bash

# プロファイリングを止めて集計する（make stackprof-report の本体）。
# drop-inを消してアプリを再起動する（停止時にdumpが書き出される）→ dumpを集計して保存・commit・push。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

STACKPROF_LIMIT="${STACKPROF_LIMIT:-40}"
OUT_DIR="$(pwd)/tmp/stackprof"
DROPIN="${SYSTEMD_PATH}/${SERVICE_NAME}.service.d/zz-stackprof.conf"

# プロファイラを外したまま再起動する。stop時のat_exitでdumpが出る
sudo rm -f "$DROPIN"
scripts/restart.sh app

shopt -s nullglob
dumps=("$OUT_DIR"/*.dump)
if [ "${#dumps[@]}" -eq 0 ]; then
  echo "dumpがありません: ${OUT_DIR}（make stackprof-on 後にベンチを回したか、アプリの停止時に書き出されたか確認）" >&2
  exit 1
fi

measure_log_meta
log_file=$(measure_log_path stackprof)
{
  measure_log_header
  echo "# dumps: ${#dumps[@]}"
  stackprof "${dumps[@]}" --text --limit "$STACKPROF_LIMIT"
} | tee "$log_file"

# 深掘り用に dump を残す（stackprof <dump> --method 'Class#method'）
keep_dir="${OUT_DIR}/done/${MEASURE_STAMP}"
mkdir -p "$keep_dir"
mv "${dumps[@]}" "$keep_dir"/
echo "dumps: ${keep_dir}" >&2

echo "saved: $log_file" >&2
scripts/push-measure-log.sh "$log_file"
