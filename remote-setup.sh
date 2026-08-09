#!/bin/bash

# サーバー上で実行するセットアップスクリプト（tarball展開〜チームリポジトリのgit配線）。
# 通常は setup.sh がローカルから `ssh ... bash -s -- <args> < remote-setup.sh` で流し込む。
#
# setup.sh が使えない・途中で失敗した場合（tar展開の権限エラー等）は、サーバー上で
# isuconユーザーとして（isuconでないユーザーなら sudo -i -u isucon した状態で）
# 単体実行して途中から再開できる:
#
#   curl -fsSL https://raw.githubusercontent.com/Yuhi-Sato/isucon-ruby-ready/main/remote-setup.sh \
#     | bash -s -- s1 <repo-name>
#
# 何度実行しても安全（冪等）。Deploy keyが未登録の場合は復旧手順を表示して終了する。

set -euo pipefail

REPO_OWNER="Yuhi-Sato"
DEFAULT_TARGET_DIR="/home/isucon"

usage() {
  echo "Usage: $0 <s1|s2|s3> <repo-name> [--dir <path>]" >&2
  echo "  s1   : tarball展開〜チームリポジトリへの初回pushまで行う" >&2
  echo "  s2/s3: チームリポジトリの取得とセットアップを行う" >&2
  echo "  --dir: 配布リポジトリのルート（webapp/と同階層）。省略時は ${DEFAULT_TARGET_DIR}" >&2
  exit 1
}

TARGET_DIR="$DEFAULT_TARGET_DIR"
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      [ "$#" -ge 2 ] || usage
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  usage
fi

ROLE="${POSITIONAL[0]}"
REPO_NAME="${POSITIONAL[1]}"

if ! echo "$ROLE" | grep -qE '^s[1-3]$'; then
  echo "エラー: 役割は s1 / s2 / s3 のいずれかで指定してください（指定値: ${ROLE}）" >&2
  usage
fi

# setup.shと同じ導出（単体実行時の引数を最小にするため、ここでも導出する）
REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
REPO_SSH_URL="git@github.com:${REPO_SLUG}.git"
KEY_BASENAME="github_deploy_${REPO_NAME}"
KEY_FILE="$HOME/.ssh/$KEY_BASENAME"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"

# このリポジトリ専用のDeploy keyだけを使う（agentや他の鍵に依存しない）
GIT_SSH_CMD="ssh -i $KEY_FILE -o IdentitiesOnly=yes"
export GIT_SSH_COMMAND="$GIT_SSH_CMD"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Deploy keyの自己修復: setup.shがisucon以外のユーザーで失敗した後は、鍵が
# そのユーザーのhomeにしか無いことがある。実行ユーザーのhomeに無ければ生成する。
if [ ! -f "$KEY_FILE" ]; then
  echo "Deploy key (${KEY_FILE}) が無いため生成します..."
  # </dev/null: bash -s（stdin経由）で実行された場合に、stdinを読みうる子プロセスが
  # 残りのスクリプトを横取りするのを防ぐ
  ssh-keygen -q -t ed25519 -N "" -f "$KEY_FILE" -C "${ROLE}-${KEY_BASENAME}" </dev/null
fi

# github.comのホストキーがknown_hostsになければssh-keyscanで追加する
if ! ssh-keygen -F github.com -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "github.comのホストキーが未登録のため追加します..."
  ssh-keyscan -H github.com >> "$KNOWN_HOSTS" 2>/dev/null
fi

# Deploy keyでのGitHub認証疎通確認
# </dev/null必須: bash -s（stdin経由）実行時、stdinを切らないとこのssh -Tが
# 残りのスクリプトを横取りし、エラーも出さずここで静かに終了してしまう。
AUTH_CHECK="$(ssh -i "$KEY_FILE" -o IdentitiesOnly=yes -T git@github.com </dev/null 2>&1 || true)"
if ! echo "$AUTH_CHECK" | grep -q "successfully authenticated"; then
  echo "エラー: Deploy keyでのGitHubへのSSH認証に失敗しました。" >&2
  echo "以下の公開鍵を ${REPO_SLUG} のDeploy keyとして登録してから、このスクリプトを再実行してください。" >&2
  echo "" >&2
  cat "$KEY_FILE.pub" >&2
  echo "" >&2
  echo "ローカルでの登録コマンド例（上記公開鍵を deploy_key.pub として保存した上で）:" >&2
  echo "  gh repo deploy-key add deploy_key.pub --repo ${REPO_SLUG} --allow-write --title ${ROLE}" >&2
  echo "" >&2
  echo "sshの応答:" >&2
  echo "$AUTH_CHECK" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# git init・origin設定・Deploy keyのcore.sshCommand固定（s1/s2/s3共通・冪等）
setup_git_remote() {
  if [ ! -d .git ]; then
    git init -b main
  else
    echo ".gitは既に初期化済みのため、git initをスキップします。"
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    if [ "$(git remote get-url origin)" != "$REPO_SSH_URL" ]; then
      git remote set-url origin "$REPO_SSH_URL"
    fi
  else
    git remote add origin "$REPO_SSH_URL"
  fi

  # 以後の git pull / push（make deploy / make bench-prep 含む）が追加設定なしで
  # このDeploy keyを使うよう、リポジトリ設定に固定する
  git config core.sshCommand "$GIT_SSH_CMD"
}

if [ "$ROLE" = "s1" ]; then
  # ISUCON運営配布リポジトリのルート（webapp/と同階層）に、このリポジトリの
  # ツール一式を展開する（既に展開済みでも上書きになるだけで冪等）。
  echo "isucon-ruby-readyのツール一式を展開します..."
  curl -fsSL https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
    | tar xz --strip-components=1

  # ツール導入・ディレクトリ準備・サーバー設定取得（env.sh作成 → make setup →
  # make set-as-s1 → make get-conf）。get-confの結果（s1/etc/配下）を
  # このあとの初回コミットに含める。
  sh server-setup.sh s1

  setup_git_remote

  # ホームディレクトリがリポジトリルートの場合（isucon14等）、git add . が
  # ランタイム・キャッシュ・鍵類（.rustup/.cargo/.ssh等で数GB）を巻き込むため、
  # ホーム直下のdot要素と配布ランタイム(local/)を除外する（初回のみ追記・冪等）。
  # .claude（スキル）と.gitignore自体は管理対象に残す。
  if ! grep -qF "# --- remote-setup.sh managed ignores ---" .gitignore 2>/dev/null; then
    cat >> .gitignore <<'IGNORE_BLOCK'
# --- remote-setup.sh managed ignores ---
/.*
!/.claude/
!/.gitignore
/local/
node_modules/
IGNORE_BLOCK
  fi

  # GitHubは100MB超のファイルのpushを拒否するため、50MB以上のファイルは
  # .gitignoreに追加して管理対象から除外する（ベンチ用初期データ等を想定）
  find . -path ./.git -prune -o -type f -size +50M -print | sed 's|^\./||' | while IFS= read -r f; do
    # 既に除外済み（managedブロックや既存.gitignoreでカバー済み）なら追記しない
    if ! git check-ignore -q "$f"; then
      echo "/$f" >> .gitignore
      echo "サイズ超過（50MB以上）のため.gitignoreに追加: $f"
    fi
    # 以前の実行で追跡済みになっていた場合はインデックスからも外す
    git rm --cached --quiet "$f" 2>/dev/null || true
  done

  git add .
  if git diff --cached --quiet; then
    echo "コミット対象の変更がないため、コミットをスキップします。"
  else
    git commit -m 'first commit'
  fi

  if ! git push -u origin main; then
    echo "エラー: git pushに失敗しました。" >&2
    echo "Deploy keyが書き込み権限付き（--allow-write）で登録されているかを確認してから再実行してください。" >&2
    exit 1
  fi
else
  # s2/s3: TARGET_DIRにはISUCON運営配布のアプリコード（webapp/等）が既に
  # 展開された状態で置かれている（非空）。git cloneは非空ディレクトリを
  # 拒否するため使えず、代わりにgit init + fetch + checkoutでチーム
  # リポジトリの内容（Makefile・tool-config・webapp含む）を被せる。
  setup_git_remote

  echo "チームリポジトリ (${REPO_SSH_URL}) からmainを取得します..."
  git fetch origin main
  git checkout -f -B main origin/main

  # ツール導入・ディレクトリ準備・サーバー設定取得（env.sh作成 → make setup →
  # make set-as-s2/s3 → make get-conf）。
  sh server-setup.sh "$ROLE"
fi

echo "サーバー側のセットアップが完了しました（role: ${ROLE}）。"
