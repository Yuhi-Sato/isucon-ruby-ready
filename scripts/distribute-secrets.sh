#!/bin/bash

# ローカルのsecrets.envを対象サーバー（s1/s2/s3）へSSH(scp)で配布する（make distribute-secrets の本体）。
# APIキーやDBパスワードなどgit管理に乗せない値をチームメンバー間で配るために使う。
# Host s1/s2/s3は~/.ssh/configに手書きする（README参照）。
# 失敗したサーバーがあっても残りへ配布を続け、最後にまとめて失敗を報告して非0で終了する。

set -euo pipefail
cd "$(dirname "$0")/.."

SECRETS_FILE="${SECRETS_FILE:-secrets.env}"
REMOTE_SECRETS_PATH="${REMOTE_SECRETS_PATH:-secrets.env}"
SERVERS="${SERVERS:-s1 s2 s3}"

[ -f "$SECRETS_FILE" ] || {
  echo "not found: ${SECRETS_FILE} (set SECRETS_FILE=<path> to override)" >&2
  exit 1
}

# 秘密情報なのでローカル側も配布前に権限を絞る
chmod 600 "$SECRETS_FILE"

FAILED=()
for HOST in $SERVERS; do
  echo "$HOST" | grep -qE '^s[1-3]$' || { echo "skip invalid host: ${HOST}" >&2; continue; }
  echo "==> ${HOST}"
  if scp -p "$SECRETS_FILE" "${HOST}:${REMOTE_SECRETS_PATH}" \
    && ssh "$HOST" "chmod 600 $(printf %q "$REMOTE_SECRETS_PATH")"; then
    echo "ok: ${HOST}"
  else
    echo "failed: ${HOST}" >&2
    FAILED+=("$HOST")
  fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "distribute-secrets failed for: ${FAILED[*]}" >&2
  exit 1
fi

echo "distributed ${SECRETS_FILE} to: ${SERVERS}"
