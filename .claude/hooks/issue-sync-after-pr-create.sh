#!/bin/bash

# `gh issue create` 実行後にだけ IssueSync の context を出す（PostToolUse hook の本体）。

set -euo pipefail

payload=$(cat)
if ! jq -e '
  (
    (.event_name? == "issues" and .action? == "opened")
    or ((.tool_input.command? // "") | test("^[[:space:]]*gh issue create([[:space:]]|$)"))
  )
' >/dev/null <<<"$payload"; then
  exit 0
fi

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "【IssueSync】GitHubのissuesイベントがaction=opened（gh issue create）の場合のみ同期する。edited、labeled、unlabeled、issue_comment、closed、reopened、assignedなどでは何もしない。"
  }
}'
