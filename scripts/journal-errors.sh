#!/bin/bash

# systemdジャーナルからwarning/errorレベルのログを抽出する（make journal-errors の本体）。
#
# 2種類の抽出を続けて出力する。
#   1. syslog優先度がwarning以上のエントリ（journalctl -p warning）
#   2. 優先度はnotice以下だが、本文がエラー相当の文言にマッチするエントリ
# Puma/Sinatraは標準出力に書いたログがjournaldではinfo(6)扱いになるため、
# 優先度だけで絞るとアプリが出した "ERROR" 行を取りこぼす。2でそれを拾う
# （標準エラー出力に出る例外はerr(3)になるので1で拾える）。
# 1と2は優先度の範囲が重ならないので、同じエントリが両方に出ることはない。
#
# 環境変数で調整する（例: make journal-errors SINCE=-10min LINES=50）。
#   UNIT      対象のsystemdユニット（デフォルト: vars.shのSERVICE_NAME）
#   SINCE     journalctlの--sinceに渡す値（デフォルト: 指定なし＝全期間）
#   UNTIL     journalctlの--untilに渡す値（デフォルト: 指定なし）
#   LINES     各セクションの最大出力行数（デフォルト: 200）
#   RAW_LINES 2で本文マッチをかける前に取得する生エントリ数（デフォルト: 5000）
#   PATTERN   2で使う正規表現（デフォルト: warn|error|fatal|exception|critical）

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

UNIT="${UNIT:-$SERVICE_NAME}"
SINCE="${SINCE:-}"
UNTIL="${UNTIL:-}"
LINES="${LINES:-200}"
RAW_LINES="${RAW_LINES:-5000}"
PATTERN="${PATTERN:-warn|error|fatal|exception|critical}"

# 全セクション共通のjournalctl引数（-nは各セクションで付ける）
common=(-u "$UNIT" --no-pager -o short-iso)
if [ -n "$SINCE" ]; then common+=(--since "$SINCE"); fi
if [ -n "$UNTIL" ]; then common+=(--until "$UNTIL"); fi

errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

# 該当0件のときにヘッダーだけ出ても分かるように、明示的に「なし」と出す。
# journalctl自体が失敗したケースを「なし」と誤表示すると「エラーが無い」と読めてしまうため、
# 終了ステータスを見て失敗は失敗として報告する。
print_section() {
  local title="$1"; shift
  local out rc
  set +e
  out="$("$@" 2>"$errfile")"
  rc=$?
  set -e
  echo "=== ${title} ==="
  if [ "$rc" -ne 0 ]; then
    echo "(取得に失敗: exit ${rc})"
    sed 's/^/  /' "$errfile" >&2
  elif [ -z "$out" ] || [ "$out" = "-- No entries --" ]; then
    # journalctlは0件でも非0を返さず "-- No entries --" を出すので、それも「なし」に寄せる
    echo "(なし)"
  else
    echo "$out"
  fi
  echo
}

# 本文マッチ。journalctlの--grepは「1件もマッチしなかった」ときにexit 1を返し、
# ジャーナル自体を読めなかった場合と区別が付かない（正常＝エラー無しを異常と誤報告してしまう）。
# そのため先にjournalctlだけを実行して終了ステータスを確定させ、絞り込みはgrepで行う。
# 生エントリをRAW_LINES件取ってから絞るので、-nを直接使う場合と違い
# 「直近RAW_LINES件のうちマッチした最新LINES件」になる。
text_match() {
  local raw
  raw="$(sudo journalctl "${common[@]}" -n "$RAW_LINES" -p notice..debug)" || return $?
  printf '%s\n' "$raw" | { grep -iE "$PATTERN" || true; } | tail -n "$LINES"
}

echo "unit=${UNIT} since=${SINCE:-(全期間)} until=${UNTIL:-(なし)} lines=${LINES}"
echo

print_section "優先度 warning 以上（emerg/alert/crit/err/warning）" \
  sudo journalctl "${common[@]}" -n "$LINES" -p warning

print_section "本文マッチ（優先度 notice 以下 / ${PATTERN}）" text_match
