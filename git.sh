#!/bin/bash

# エラーが発生した場合にスクリプトを終了する
set -e

# 引数として Git リポジトリの URL を受け取る
if [ -z "$1" ]; then
  echo "Usage: $0 <repository-url>"
  exit 1
fi

REPO_URL="$1"

# git の初期化
git init

# リモートリポジトリを追加
echo "Adding remote repository: $REPO_URL"
git remote add origin "$REPO_URL"

# Deploy keyの登録（gh CLIが認証済みならSSH公開鍵を自動登録する。未認証なら手動登録を促す）
SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
REPO_SLUG=$(echo "$REPO_URL" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  # リポジトリが未作成なら gh repo create で新規作成する（private固定）
  if ! gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
    echo "リポジトリ $REPO_SLUG が見つからないため、gh repo create で新規作成します（private）..."
    gh repo create "$REPO_SLUG" --private
  fi

  echo "Registering deploy key via gh CLI..."
  # --allow-write を付けないとread-only鍵になり、後続のgit pushが失敗する
  gh repo deploy-key add "$SSH_KEY_PATH" --title "$(hostname)" --allow-write -R "$REPO_SLUG"
else
  echo "gh CLIが未認証のため、リポジトリ作成とデプロイキーの自動登録をスキップしました。"
  echo "https://github.com/new から $REPO_SLUG （private推奨）を作成した上で、以下の公開鍵をDeploy keyとして登録してから続行してください（Allow write accessに必ずチェックを入れる。入れないと後続のgit pushが失敗する）:"
  cat "$SSH_KEY_PATH"
  read -p "登録が完了したらEnterを押してください..." _
fi

# .gitignore はtarball展開時に配置済みのため、ここでは生成しない

# Makefile のクエリ抽出コマンドを実行
echo "Running 'make extract-queries'..."
make extract-queries

# 初期コミット
echo "Adding and committing initial files..."
git add .
git commit -m 'first commit'

# ブランチの作成とプッシュ
echo "Setting up main branch..."
git branch -M main
if ! git push -u origin main; then
  echo "git pushに失敗しました。Deploy keyの設定を確認してください:"
  echo "  https://github.com/$REPO_SLUG/settings/keys に $(hostname) という名前のDeploy keyが登録されているか"
  echo "  Allow write accessが有効になっているか（無効だとpushはpermission deniedになる）"
  echo "確認・修正後、'git push -u origin main' を再実行してください。"
  exit 1
fi

echo "Git repository setup complete."
