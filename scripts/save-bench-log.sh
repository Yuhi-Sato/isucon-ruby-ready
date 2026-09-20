#!/bin/bash

# ベンチマークサーバーのGUIに表示された結果（スコア・エラー・警告など）を標準入力から受け取り、
# docs/bench/ 以下に「日時-ブランチ-コミット」のファイル名で保存する（make save-bench-log の本体）。
# ローカル（GUIを見ている手元のマシン）で、ベンチを回したブランチをcheckoutした状態で実行する。
# 分析は .claude/skills/isucon-benchmark-log-analysis を参照。
#
#   pbpaste | make save-bench-log          # macOS
#   xclip -o | make save-bench-log         # Linux
#   make save-bench-log < result.txt       # ファイルから

set -euo pipefail
cd "$(dirname "$0")/.."

BENCH_LOG_DIR=docs/bench

if [ -t 0 ]; then
  echo "usage: pbpaste | make save-bench-log  (GUIの結果を標準入力から渡す)" >&2
  exit 1
fi

body=$(cat)
if [ -z "${body//[[:space:]]/}" ]; then
  echo "error: 標準入力が空です。GUIの結果をコピーしてから実行してください" >&2
  exit 1
fi

stamp=$(date "+%Y%m%d-%H%M%S")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')
branch="${branch:-no-git}"
hash=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
mkdir -p "$BENCH_LOG_DIR"
out="${BENCH_LOG_DIR}/${stamp}-${branch}-${hash}.md"

{
  echo "# ベンチ結果 ${stamp}"
  echo
  echo "- 日時: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- ブランチ: ${branch}"
  echo "- コミット: ${hash}"
  echo "- メモ: "
  echo
  echo '```'
  printf '%s\n' "$body"
  echo '```'
} > "$out"

echo "saved: $out"
echo "次: git add $out && git commit -m 'ベンチ結果を記録'" >&2
