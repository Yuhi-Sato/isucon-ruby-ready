#!/bin/bash

# サーバー上で実行するセットアップスクリプト。
# 通常は setup.sh がローカルから SSH 経由で呼び出すが、ローカル経由が使えない
# 異常時（gh未認証等）はサーバー上で直接 `sh server-setup.sh <role>` を実行する
# フォールバック手段としても使える。

# setup.sh・README双方の想定呼び出しが `sh server-setup.sh <role>` であり、
# Ubuntuの/bin/shはdash（pipefail非対応のPOSIX sh）のため、bash専用の
# `-o pipefail` は使わない。
set -eu
cd "$(dirname "$0")"

if [ "$#" -ne 1 ] || ! echo "$1" | grep -qE '^s[1-3]$'; then
  echo "Usage: $0 <s1|s2|s3>" >&2
  exit 1
fi

ROLE="$1"

# env.sh が存在しない場合は作成する
ENV_FILE="/home/isucon/env.sh"
if [ ! -e "$ENV_FILE" ]; then
  echo "Creating $ENV_FILE..."
  touch "$ENV_FILE"
  echo "$ENV_FILE を作成しました。"
else
  echo "$ENV_FILE は既に存在します。"
fi

# Makefile のコマンドでセットアップを行う
echo "Running setup commands from Makefile (role: $ROLE)..."
make setup
make "set-as-$ROLE"
make get-conf
