#!/bin/bash

# ベンチ終了後の記録をまとめて行う（make bench-done の本体）。ローカルで実行する。
#   1. 標準入力のポータル結果を docs/bench/ に保存してcommitする（scripts/save-bench-log.sh）
#   2. 全サーバーで alp / slow-query を集計し、Discord通知・measure-logs のcommit/pushを行う（make remote-nd-all）
#      SSHが通らない環境（Claude Code on the web 等）では警告だけ出してスキップする。
#      その場合は手元で make remote-nd-all を実行し、git pull で measure-logs を取り込む
#   3. サーバーがpushした measure-logs を取り込み（git pull --rebase）、ベンチ結果のcommitをpushする
# 分析（スコアストラテジー）はここでは行わない。.claude/skills/isucon-score-strategy に引き継ぐ。
#
#   pbpaste | make bench-done              # macOS
#   make bench-done < result.txt           # ファイルから
#   SERVERS="s1 s2" make bench-done        # nd の対象サーバーを絞る

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -t 0 ]; then
  echo "usage: pbpaste | make bench-done  (ポータルの結果を標準入力から渡す)" >&2
  exit 1
fi

branch=$(git symbolic-ref --quiet --short HEAD) || { echo "detached HEADでは実行できない（ベンチしたブランチをcheckoutする）" >&2; exit 1; }

# 1. ベンチ結果の保存・commit
scripts/save-bench-log.sh

# 2. alp / slow-query の通知（SSHが通るときだけ）
# SERVERS は Makefile 側で := 定義されているため、環境変数ではなく make の引数として渡す
first_server=$(echo "${SERVERS:-s1}" | awk '{print $1}')
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$first_server" true 2>/dev/null; then
  make remote-nd-all ${SERVERS:+SERVERS="$SERVERS"} \
    || echo "warning: 一部のサーバーで make nd に失敗した（上の出力を確認。計測ログはサーバー側に残る）" >&2
else
  echo "warning: ${first_server} にSSHできないため make remote-nd-all をスキップした" >&2
  echo "  手元で make remote-nd-all を実行し、その後 git pull で measure-logs を取り込むこと" >&2
fi

# 3. サーバーからの measure-logs を取り込み、ベンチ結果のcommitをpushする
git pull --rebase --autostash origin "$branch"
git push -u origin "$branch"

echo "bench-done: docs/bench の保存・push が完了。次は isucon-score-strategy で分析する"
