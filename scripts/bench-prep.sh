#!/bin/bash

# ベンチマーク直前に実行する（make bench-prep の本体）。
# ログ削除・設定反映・DB/nginx含む全再起動を伴う。
# git pull 後にリポジトリ内の他スクリプトを呼ぶため、それらは常にpull済みの最新版で実行される。

set -euo pipefail
cd "$(dirname "$0")/.."

# ブランチ未指定時はmainをpullする（作業ツリーが別ブランチのまま古い状態でベンチを回さないため）
BRANCH="${BRANCH:-main}"
./scripts/checkout-branch.sh "$BRANCH"
git pull origin "$BRANCH"

# main以外のブランチでは最新のorigin/mainを取り込む（mainに入った他の施策を外したままベンチを回さないため）。
# 取り込んだ結果はoriginのブランチへpushし、サーバーの作業ツリーとoriginをそろえる
if [ "$BRANCH" != "main" ]; then
  git fetch origin main
  if ! git merge --no-edit origin/main; then
    git merge --abort
    echo "origin/main を ${BRANCH} にマージできませんでした（コンフリクト）。ローカルで main を取り込んで push してから再実行してください" >&2
    exit 1
  fi
  git push origin "HEAD:${BRANCH}" || echo "warning: origin/${BRANCH} へのpushに失敗（ベンチ準備は続行する）" >&2
fi

. scripts/vars.sh
scripts/check-server-id.sh
(cd "$APP_DIR" && bundle config set --local without test && bundle install)
scripts/rm-logs.sh
scripts/deploy-conf.sh
scripts/restart.sh all

# ベンチ走行中のtop計測はbench-prep完了直後からベンチ開始までのタイムラグを読めないため、
# ここでバックグラウンド起動しておく（手動で別途叩く必要をなくす）。
# setsidでSSHセッションから切り離し、sshが切れても計測・保存（push-measure-log.sh）まで走り切らせる
TOP_DELAY="${TOP_DELAY:-40}" setsid scripts/top.sh </dev/null >/dev/null 2>&1 &
disown
