#!/bin/bash

# Claude が作業を終えて止まる時に、作業ブランチにPRが無ければ停止を止めてPR作成へ戻す（Stop hook の本体）。
# commit だけ積んでPRを作り忘れ、レビューもベンチ比較もされないブランチを残さないため。
# main・mainより先のcommitが無いブランチ・PR作成済みのブランチでは何もしない。
# 変更がベンチ結果と計測ログ（docs/bench/・measure-logs/）だけなら、ログを出して終わる作業なので止めない。
# 判断と本文作成はClaudeが行う。手順は .claude/skills/create-pr/SKILL.md 参照。

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)

# hook に戻されて再度止まる時は通す（承認待ちで止まるたびに戻すループを防ぐ）
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0

branch=$(git branch --show-current 2>/dev/null)
case "$branch" in
  main|master|"") exit 0 ;;
esac

base=origin/main
git rev-parse --verify -q "$base" >/dev/null || base=main
ahead=$(git rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
dirty=$(git status --porcelain 2>/dev/null)

[ "$ahead" -eq 0 ] && [ -z "$dirty" ] && exit 0

changed=$( { git diff --name-only "$base...HEAD" 2>/dev/null; cut -c4- <<<"$dirty"; } \
  | grep -v -E '^(docs/bench/|measure-logs/)' | grep -v '^$')
[ -z "$changed" ] && exit 0

# PRが既にあれば（OPEN/MERGED/CLOSEDを問わず）何もしない
# gh pr view はGraphQLを使い、Claude Code のクラウド環境では403になるためREST APIで引く。
# 確認自体に失敗したら（未ログイン・ネットワーク不通など）PRの有無が分からないので止めない
prs=$(gh api "repos/{owner}/{repo}/pulls?state=all&head={owner}:$branch" --jq 'length' 2>/dev/null) || exit 0
[ "$prs" != "0" ] && exit 0

note=""
[ -n "$dirty" ] && note="未コミットの変更があるので、先にテストを実行してcommitする（CLAUDE.md の原則）。"

jq -n --arg branch "$branch" --arg note "$note" '{
  decision: "block",
  reason: ("【作業終了前の確認】ブランチ \($branch) にPRがまだ無い。\($note).claude/skills/create-pr/SKILL.md の本文構成と作成手順に従い、本文案をユーザに見せて承認を得てから push と gh pr create を行う。作業が途中でPRを作る段階でないなら、その旨をユーザに伝えて止まってよい。")
}'
