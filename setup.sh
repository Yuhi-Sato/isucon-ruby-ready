#!/bin/bash

# ローカル実行専用スクリプト。
# サーバーにはGitHub認証情報を一切置かず、ローカルのgh CLI認証とSSH agent
# forwardingだけを使って、チームリポジトリのgit初期化・初回pushを行う。
# 旧git.sh（サーバー上で実行し、サーバーごとにDeploy keyをGitHubへ登録する方式）の後継。

set -euo pipefail

REPO_OWNER="Yuhi-Sato"
TARGET_DIR="/home/isucon"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <user@server> [repo-name]" >&2
  exit 1
fi

SERVER="$1"
REPO_NAME="${2:-ISUCON-$(date +%Y%m%d%H%M%S)}"
REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
REPO_SSH_URL="git@github.com:${REPO_SLUG}.git"

echo "リポジトリ: ${REPO_SLUG}"
if [ "$#" -lt 2 ]; then
  echo "（repo-name省略のため上記の名前を新規採番。2台目以降や再実行では明示的に指定すること）"
fi

# --- ローカル側の前提チェック ---

if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh CLIが見つかりません。https://cli.github.com/ からインストールしてください。" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "エラー: gh CLIが未認証です。'gh auth login' を実行してから再実行してください。" >&2
  exit 1
fi

if ! ssh-add -l >/dev/null 2>&1; then
  echo "ssh-agentに鍵が登録されていないため、ssh-add で登録を試みます..."
  if ! ssh-add; then
    echo "エラー: ssh-add に失敗しました。ssh-agentが起動しているか、鍵のパスフレーズを確認してください。" >&2
    exit 1
  fi
fi

# --- リポジトリ作成（既に存在すればスキップ。冪等） ---

if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
  echo "リポジトリ ${REPO_SLUG} は既に存在します。"
else
  echo "リポジトリ ${REPO_SLUG} が見つからないため、gh repo create で新規作成します（private）..."
  gh repo create "$REPO_SLUG" --private
fi

# --- サーバー側処理（ssh -A で1回のSSH接続に集約する） ---

echo "サーバー ${SERVER} 上でリポジトリのセットアップを行います..."

# ここではローカルの変数をヒアドキュメント内で展開させず、
# bash -s -- の位置引数としてサーバー側スクリプトへ渡す。
ssh -A "$SERVER" bash -s -- "$TARGET_DIR" "$REPO_SSH_URL" <<'REMOTE_SCRIPT'
set -euo pipefail

TARGET_DIR="$1"
REPO_SSH_URL="$2"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"

# github.comのホストキーがknown_hostsになければssh-keyscanで追加する
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! ssh-keygen -F github.com -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "github.comのホストキーが未登録のため追加します..."
  ssh-keyscan -H github.com >> "$KNOWN_HOSTS" 2>/dev/null
fi

# agent forwardingの疎通確認
AUTH_CHECK="$(ssh -T git@github.com 2>&1 || true)"
if ! echo "$AUTH_CHECK" | grep -q "successfully authenticated"; then
  echo "エラー: GitHubへのSSH認証に失敗しました。ssh -A で接続されていない可能性があります。" >&2
  echo "$AUTH_CHECK" >&2
  exit 1
fi

cd "$TARGET_DIR"

# git初期化（初期化済みならスキップ）
if [ ! -d .git ]; then
  git init -b main
else
  echo ".gitは既に初期化済みのため、git initをスキップします。"
fi

# originリモートの設定（設定済みならスキップ）
if git remote get-url origin >/dev/null 2>&1; then
  if [ "$(git remote get-url origin)" != "$REPO_SSH_URL" ]; then
    git remote set-url origin "$REPO_SSH_URL"
  fi
else
  git remote add origin "$REPO_SSH_URL"
fi

# クエリ抽出（Makefileがなければ警告してスキップ）
if [ -f Makefile ]; then
  make extract-queries
else
  echo "警告: Makefileが見つからないため、'make extract-queries' をスキップします。"
fi

# 初回コミット（コミット対象がなければスキップ）
git add .
if git diff --cached --quiet; then
  echo "コミット対象の変更がないため、コミットをスキップします。"
else
  git commit -m 'first commit'
fi

# push（失敗時はagent forwardingの確認を促す）
if ! git push -u origin main; then
  echo "エラー: git pushに失敗しました。" >&2
  echo "ローカルのssh-agentに鍵が登録された状態でssh -A接続しているか、" >&2
  echo "リポジトリへの書き込み権限（gh CLIの認証ユーザー）があるかを確認してから再実行してください。" >&2
  exit 1
fi

echo "サーバー側のセットアップが完了しました。"
REMOTE_SCRIPT

echo "setup.shが完了しました: ${SERVER}:${TARGET_DIR} -> ${REPO_SSH_URL}"
