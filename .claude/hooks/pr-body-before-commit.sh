#!/bin/bash

# 作業ブランチで git commit する前に、そのブランチのPR本文を context に出す（PreToolUse hook の本体）。
# 本文が今の状態からずれたまま commit を重ねないため。main では何も出さない。
# 書き方は .claude/skills/create-pr、運用は .claude/skills/branch-pr-workflow を参照。

set -uo pipefail

branch=$(git branch --show-current 2>/dev/null)
case "$branch" in
  main|master|"") exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

pr=$(gh pr view --json number,state,title,body \
  -q '"#\(.number) [\(.state)] \(.title)\n\n\(.body)"' 2>/dev/null) \
  || pr="このブランチにPRはまだ無い。先に create-pr でドラフトPRを作る"

jq -n --arg branch "$branch" --arg pr "$pr" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("【commit前の確認】ブランチ \($branch) のPR本文:\n\n\($pr)\n\n本文の「変更」「実測値」「マージ条件」は、この commit を含めた状態と合っているか。ずれるなら、commit の前に本文を直す（branch-pr-workflow「PR本文と現状図の更新」）。")
  }
}'
