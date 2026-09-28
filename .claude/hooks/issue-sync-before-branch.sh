#!/bin/bash

# ブランチを新規作成する git コマンドの前に、issue-sync のトリガー1を context に出す（PreToolUse hook の本体）。
# 競合検知（未クローズissueの確認）をブランチ作成前に強制想起させるため。
# 判断自体はClaudeが行う。手順は .claude/skills/issue-sync/SKILL.md 参照。

set -uo pipefail

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: "【ブランチ作成前の確認】.claude/skills/issue-sync/SKILL.md の「トリガー1」に従い、対象エンドポイントの未クローズissueが無いか gh issue list --state open で確認してからブランチを切る。見つかったらブランチを切らずに止めてユーザに提示する。"
  }
}'
