#!/bin/bash

# エラーが発生した場合にスクリプトを終了する
set -e

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
echo "Running setup commands from Makefile..."
make setup
make set-as-s1
make get-conf
