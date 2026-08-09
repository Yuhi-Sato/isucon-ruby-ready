#!/bin/bash

# 手動デプロイ（make deploy / make remote-deploy-*）のエントリポイント。
# git pull 後に scripts/deploy.sh（pull済みの最新版。bundle install→デーモン再起動）へ
# 委譲するので、デプロイロジックの変更は同じデプロイで反映される。
# 既知の制約: このファイル自体への変更だけは `git pull` より前に読み込まれるため、
# 1回のデプロイでは反映されず、次のデプロイから反映される。

set -euo pipefail
cd "$(dirname "$0")"

# GitHub Actions からのSSHは非ログイン・非対話シェルのため、
# rbenv/xbuildでインストールしたRubyのPATHが通らないことがある。明示的に読み込む。
# shellcheck disable=SC1091
[ -f "$HOME/env.sh" ] && . "$HOME/env.sh"
export PATH="$HOME/local/ruby/bin:$HOME/.rbenv/shims:$PATH"

git pull
exec ./scripts/deploy.sh
