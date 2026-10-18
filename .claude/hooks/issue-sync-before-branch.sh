#!/bin/bash

# ブランチを新規作成する git コマンドの前に、issue-sync のトリガー1を context に出す（PreToolUse hook の本体）。
# 割り当て済みissueの有無と競合の確認をブランチ作成前に強制想起させるため。
# 判断自体はClaudeが行う。手順は .claude/skills/issue-sync/SKILL.md 参照。

set -uo pipefail

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: "【ブランチ作成前の確認】.claude/skills/issue-sync/SKILL.md の「トリガー1」に従い、gh issue list --state open で、対象エンドポイントのissueが自分に割り当てられていて、他のissueやPRと競合していないことを確認してからブランチを切る。issueが無い・他の人に割り当て済み・競合がある場合はブランチを切らずに止めてユーザに提示する（実装担当は自分で起票しない）。"
  }
}'
