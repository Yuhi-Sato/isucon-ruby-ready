#!/bin/bash

# `gh pr create` 実行後に、issue-sync のトリガー2を context に出す（PostToolUse hook の本体）。
# 対応issueへのPRリンク追記を、PR作成と同じ作業内で強制想起させるため。
# 判断自体はClaudeが行う。手順は .claude/skills/issue-sync/SKILL.md 参照。

set -uo pipefail

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "【PR作成後の確認】.claude/skills/issue-sync/SKILL.md の「トリガー2」に従い、対応issueに gh issue comment で今作ったPRのURLを追記する。"
  }
}'
