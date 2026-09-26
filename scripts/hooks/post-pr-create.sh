#!/bin/bash

# Claude Code の PostToolUse hook（.claude/settings.json から呼ばれる）。
# `gh pr create`（Bash）または GitHub MCP の create_pull_request でPRが作られた直後に、
# 「デプロイ → ベンチ → ベンチ終了の合図で isucon-score-strategy（保存・通知・分析）」という次の手順を
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
3. 「ベンチ終わった」の合図とポータルの結果が貼られたら、isucon-score-strategy スキルを起動する。
   スキルの手順0で make save-bench-log（docs/bench へ保存・commit）→ make remote-nd-all（alp/slow-queryの
   Discord通知と measure-logs の push）→ git pull --rebase / push を行い、そのあと次の一手を決める。
   SSHできない環境では make remote-nd-all をユーザーに手元で実行してもらう。"

# JSON文字列として安全に埋め込む（改行と二重引用符・バックスラッシュをエスケープ）
escaped=$(printf '%s' "$context" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed -e 's/\\n$//')

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$escaped"
