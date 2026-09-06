#!/bin/bash

# ローカルから対象サーバーへ処理を流す（make remote-deploy-s1 等の本体）。
# Host s1/s2/s3 は ~/.ssh/config に手書きする（README参照）。

set -euo pipefail

HOST="${1:-}"
ACTION="${2:-deploy}"
NOTIFY_TARGET="${3:-}"
REMOTE_DEPLOY_PATH="${REMOTE_DEPLOY_PATH:-/home/isucon}"

echo "$HOST" | grep -qE '^s[1-3]$' || {
  echo "usage: $0 s1|s2|s3 [deploy|deploy-conf|bench-prep|notify-discord] [alp|slow-query]" >&2
  exit 1
}

case "$ACTION" in
  deploy)
    ssh "$HOST" "cd $(printf %q "$REMOTE_DEPLOY_PATH") && make deploy"
    ;;
  deploy-conf)
    ssh "$HOST" "cd $(printf %q "$REMOTE_DEPLOY_PATH") && git pull && make deploy-conf && make restart"
    ;;
  bench-prep)
    # bench-prep.sh 側で git pull する
    ssh "$HOST" "cd $(printf %q "$REMOTE_DEPLOY_PATH") && make bench-prep"
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
