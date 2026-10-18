#!/bin/bash

# stackprofのインストール（make install-stackprof の本体）。後半戦のCPUプロファイリング用。
# アプリのGemfileは変更しない（boot.rbがbundler起動前に読み込むため、システム側のgemとして入れる）。
# gemの導入先はsetup前提のRubyなので、sudoは使わない。

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/vars.sh

if gem list -i stackprof >/dev/null 2>&1; then
  echo "stackprof is already installed: $(gem list stackprof | grep '^stackprof')" >&2
else
  # ネイティブ拡張のビルドに必要
  sudo NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
  gem install stackprof --no-document
fi

# CLI（レポート生成に使う）が PATH 上にあることを確認する
command -v stackprof >/dev/null || { echo "stackprof CLI が PATH にありません" >&2; exit 1; }
echo "ok: $(command -v stackprof)" >&2
