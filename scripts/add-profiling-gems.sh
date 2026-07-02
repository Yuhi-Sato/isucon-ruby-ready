#!/bin/bash

# 重要: このスクリプトは手元のリポジトリで実行し、Gemfile / Gemfile.lock の変更を
# コミット・pushするフローを想定している。サーバー上で直接実行しないこと。
# サーバー上で実行するとワーキングツリーに変更が残り、以後の `git pull`
# （make bench / make deploy の先頭ステップ）がconflictで失敗する。

set -euo pipefail

APP_DIR="${1:-.}"
cd "$APP_DIR"

bundle add vernier
