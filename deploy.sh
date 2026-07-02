#!/bin/bash

# CI（GitHub Actions）・手動デプロイの両方から呼ばれるエントリポイント。
# 既知の制約: このファイル自体への変更は次回の `git pull` (make deploy 内) より前に
# 実行されるため、1回のデプロイでは反映されず、次のデプロイから反映される。

set -euo pipefail
cd "$(dirname "$0")"

# GitHub Actions からのSSHは非ログイン・非対話シェルのため、
# rbenv/xbuildでインストールしたRubyのPATHが通らないことがある。明示的に読み込む。
# shellcheck disable=SC1091
[ -f "$HOME/env.sh" ] && . "$HOME/env.sh"
export PATH="$HOME/local/ruby/bin:$HOME/.rbenv/shims:$PATH"

make deploy
