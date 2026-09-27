#!/bin/bash

# Claude Code の PostToolUse hook（.claude/settings.json から呼ばれる）。
# `gh pr create`（Bash）または GitHub MCP の create_pull_request でPRが作られた直後に、
# 「デプロイ → ベンチ → ベンチ終了の合図で記録・計測 → マージの確認」という次の手順を
# additionalContext としてClaudeに返す。デプロイ自体はここでは行わない
# （別のメンバーがベンチ中のサーバーを上書きしないよう、Claudeがユーザーに確認してから実行する）。
#
# 標準入力にはhookのJSON（tool_name / tool_input.command / tool_response.stdout など）が渡される。
# jq に依存しないよう grep だけで判定する。該当しない呼び出しでは何も出力せず exit 0 する。

set -uo pipefail

input=$(cat)

pr_url=$(printf '%s' "$input" | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | head -1)

# Bash の場合は「コマンドに gh pr create を含む」だけだと、その文字列を含む grep や echo でも発火してしまう。
# gh pr create は成功時に作成したPRのURLを出力するので、URLが取れたことも条件にする
is_pr_create=0
if printf '%s' "$input" | grep -qE '"tool_name": *"Bash"' \
  && printf '%s' "$input" | grep -qE 'gh +pr +create' \
  && [ -n "$pr_url" ]; then
  is_pr_create=1
elif printf '%s' "$input" | grep -qE '"tool_name": *"mcp__github__create_pull_request"'; then
  is_pr_create=1
fi
[ "$is_pr_create" = 1 ] || exit 0

branch=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

context="PRを作成した${pr_url:+: ${pr_url}}。ISUCONの1実験としてこのPRを扱う。次の手順を順に進めること。
1. ユーザーに「s1へデプロイしてベンチ待ちに入るか」を確認する（別のメンバーがベンチ中なら上書きしてしまうため、勝手に実行しない）。
   了承されたら: make remote-bench-prep-s1 BRANCH=${branch:-<ブランチ名>}
   この環境からSSHできない（Claude Code on the web など）場合は、ユーザーに手元で同じコマンドを実行してもらう。
2. ユーザーがポータルでベンチを実行する。終了はhookでは検知できないので、ユーザーの合図を待つ。
3. 「ベンチ終わった」の合図とポータルの結果が貼られたら、確認なしで記録・計測する
   （次のbench-prepでサーバー上のログが上書きされるため後回しにしない。マージより先に済ませ、ログをPRブランチに載せる）。
   PRブランチをcheckoutした状態で: 貼られた結果を一字も変えずに make save-bench-log へ渡す（docs/bench へ保存・commit）
   → make remote-measure-all（alp/slow-query をサーバーで実行し measure-logs を push）→ git pull --rebase / git push。
   SSHできない環境では make remote-measure-all をユーザーに手元で実行してもらう。
4. isucon-score-strategy スキルは起動せず、レポートも書かない。
   今回のスコアと docs/bench/ の直前のログのスコアを1行で並べ、「mainへマージしますか？」とユーザーに確認する。
   勝手にマージしない。了承されたら: gh pr merge ${pr_url:-<PRのURL>} --merge
   戦略の分析はユーザーから依頼されたときだけ行う（手順3で記録・計測は済んでいるので、スキルの手順0はやり直さない）。"

# JSON文字列として安全に埋め込む（改行と二重引用符・バックスラッシュをエスケープ）
escaped=$(printf '%s' "$context" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed -e 's/\\n$//')

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$escaped"
