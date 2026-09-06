#!/bin/bash

# ローカルから対象サーバーへ処理を流す（make remote-deploy-s1 等の本体）。
# Host s1/s2/s3 は ~/.ssh/config に手書きする（README参照）。

set -euo pipefail

HOST="${1:-}"
ACTION="${2:-deploy}"
BRANCH="${3:-}"
NOTIFY_TARGET="${4:-}"
REMOTE_DEPLOY_PATH="${REMOTE_DEPLOY_PATH:-/home/isucon}"

echo "$HOST" | grep -qE '^s[1-3]$' || {
  echo "usage: $0 s1|s2|s3 [deploy|deploy-conf|bench-prep|notify-discord] [alp|slow-query]" >&2
  exit 1
}

if [ "$ACTION" = notify-discord ]; then
  NOTIFY_TARGET="$BRANCH"
  BRANCH=""
fi

if [ -n "$BRANCH" ]; then
  git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || {
    echo "invalid branch name: $BRANCH" >&2
    exit 1
  }
fi

REMOTE_CD="cd $(printf %q "$REMOTE_DEPLOY_PATH")"
REMOTE_BRANCH=""
if [ -n "$BRANCH" ]; then
  REMOTE_BRANCH="git fetch origin $(printf %q "$BRANCH") && git checkout -B $(printf %q "$BRANCH") origin/$(printf %q "$BRANCH") && git pull origin $(printf %q "$BRANCH") && "
fi

case "$ACTION" in
  deploy)
    ssh "$HOST" "$REMOTE_CD && ${REMOTE_BRANCH}make deploy"
    ;;
  deploy-conf)
    ssh "$HOST" "$REMOTE_CD && ${REMOTE_BRANCH}$(if [ -z "$BRANCH" ]; then printf 'git pull && '; fi)make deploy-conf && make restart"
    ;;
  bench-prep)
    # bench-prep.sh 側で git pull する
    ssh "$HOST" "$REMOTE_CD && ${REMOTE_BRANCH}make bench-prep"
    ;;
  notify-discord)
    echo "$NOTIFY_TARGET" | grep -qE '^(alp|slow-query)$' || {
      echo "usage: $0 s1|s2|s3 notify-discord alp|slow-query" >&2
      exit 1
    }
    ssh "$HOST" "cd $(printf %q "$REMOTE_DEPLOY_PATH") && make notify-discord-$(printf %q "$NOTIFY_TARGET")"
    ;;
  *)
    echo "unknown action: ${ACTION} (expected deploy / deploy-conf / bench-prep / notify-discord)" >&2
    exit 1
    ;;
esac
