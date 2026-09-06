#!/bin/bash

# 指定されたoriginのブランチをサーバーの作業ツリーへ反映する。
# ブランチ未指定時は、現在のブランチをそのまま使う。

set -euo pipefail
cd "$(dirname "$0")/.."

BRANCH="${1:-}"
[ -n "$BRANCH" ] || exit 0

git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || {
  echo "invalid branch name: $BRANCH" >&2
  exit 1
}

git fetch origin "$BRANCH"
git checkout -B "$BRANCH" "origin/$BRANCH"
