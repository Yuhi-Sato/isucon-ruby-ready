#!/bin/bash

# サーバー上で実行するセットアップスクリプト（チームリポジトリの取得〜配布コードのpush）。
# 通常は setup.sh がローカルから `ssh ... bash -s -- <args> < remote-setup.sh` で流し込む。
#
# GitHubへの認証はssh agent forwardingで行う。このスクリプトはサーバー上に鍵を作らず、
# 転送されてきたローカルのssh-agentをそのまま使う。したがって **agent転送付きの
# SSHセッションから実行する必要がある**（setup.sh経由なら自動的にそうなる）。
#
# setup.sh が使えない・途中で失敗した場合は、サーバー上で isuconユーザーとして
# 単体実行して途中から再開できる。冪等なので何度実行しても安全。
#
#   ssh -A s1                      # agent転送付きでログインする
#   cd /home/isucon && bash remote-setup.sh s1 <owner>/<repo>
#
# サーバー上にこのファイルがまだ無い場合は、テンプレート本体から取得する:
#
#   curl -fsSL https://raw.githubusercontent.com/Yuhi-Sato/isucon-ruby-ready/main/remote-setup.sh \
#     | bash -s -- s1 <owner>/<repo>

set -euo pipefail

DEFAULT_TARGET_DIR="/home/isucon"

die() { echo "エラー: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
Usage: remote-setup.sh <s1|s2|s3> <owner/repo> [--dir <path>]

  s1   : チームリポジトリを取得し、配布アプリコードを初回pushする
  s2/s3: チームリポジトリ（s1がpush済み）を取得してセットアップする
  --dir: 配布リポジトリのルート（webapp/と同階層）。省略時は /home/isucon
USAGE
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

[ "${#POSITIONAL[@]}" -eq 2 ] || usage

ROLE="${POSITIONAL[0]}"
REPO="${POSITIONAL[1]}"

echo "$ROLE" | grep -qE '^s[1-3]$' \
  || die "役割は s1 / s2 / s3 のいずれかで指定してください（指定値: ${ROLE}）"

case "$REPO" in
  */*/*|*/|/*) die "第2引数は owner/repo 形式で指定してください（指定値: ${REPO}）" ;;
  */*) : ;;
  *) die "第2引数は owner/repo 形式で指定してください。リポジトリ名だけでは足りません（指定値: ${REPO}）" ;;
esac

REPO_SSH_URL="git@github.com:${REPO}.git"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# github.comのホストキーがknown_hostsになければssh-keyscanで追加する
if ! ssh-keygen -F github.com -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "github.comのホストキーが未登録のため追加します..."
  ssh-keyscan -H github.com >> "$KNOWN_HOSTS" 2>/dev/null
fi

# --- 転送されてきたssh-agentでGitHubに認証できるかの確認 ---
# </dev/null必須: bash -s（stdin経由）実行時、stdinを切らないとこのssh -Tが
# 残りのスクリプトを横取りし、エラーも出さずここで静かに終了してしまう。
AUTH_CHECK="$(ssh -T git@github.com </dev/null 2>&1 || true)"
if ! echo "$AUTH_CHECK" | grep -q "successfully authenticated"; then
  echo "エラー: GitHubへのSSH認証に失敗しました。ssh agent forwardingが届いていません。" >&2
  echo "" >&2
  echo "  SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-(未設定)}" >&2
  echo "  転送されている鍵:" >&2
  if command -v ssh-add >/dev/null 2>&1; then
    ssh-add -l 2>&1 | sed 's/^/    /' >&2 || true
  else
    echo "    (ssh-addコマンドが見つかりません)" >&2
  fi
  echo "" >&2
  echo "確認すること:" >&2
  echo "  1. ローカルの ~/.ssh/config の Host ${ROLE} に ForwardAgent yes があるか" >&2
  echo "     （setup.sh が管理ブロックに自動で書き込む）" >&2
  echo "  2. ローカルで ssh-add -l に鍵が出るか。出なければ ssh-add <鍵> する" >&2
  echo "  3. その鍵がGitHubのSettings > SSH and GPG keysに登録されているか" >&2
  echo "  4. 手動実行の場合は ssh -A でログインしているか" >&2
  echo "" >&2
  echo "sshの応答:" >&2
  echo "$AUTH_CHECK" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# git init・origin設定（s1/s2/s3共通・冪等）
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

  # 旧方式（Deploy key）でセットアップ済みのサーバーからの移行。
  # core.sshCommandが残っていると転送されたagentではなく消えた鍵を見に行く。
  git config --unset core.sshCommand 2>/dev/null || true
}

# GitHubは100MB超のファイルのpushを拒否するため、50MB以上のファイルは
# .gitignoreに追加して管理対象から除外する（ベンチ用初期データ等を想定）
exclude_large_files() {
  find . -path ./.git -prune -o -type f -size +50M -print | sed 's|^\./||' | while IFS= read -r f; do
    # 既に除外済み（.gitignoreでカバー済み）なら追記しない
    if ! git check-ignore -q "$f"; then
      echo "/$f" >> .gitignore
      echo "サイズ超過（50MB以上）のため.gitignoreに追加: $f"
    fi
    # 以前の実行で追跡済みになっていた場合はインデックスからも外す
    git rm --cached --quiet "$f" 2>/dev/null || true
  done
}

# 配布リポジトリのルートがホームディレクトリそのものになる問題（isucon14等）では、
# .gitignoreの除外が効かないと秘密鍵ごとpushされる。最後の防波堤として確認する。
assert_no_secrets_staged() {
  local hits
  hits="$(git diff --cached --name-only \
    | grep -E '(^|/)\.(ssh|aws|gnupg)/|(^|/)id_(rsa|ecdsa|ed25519)$' || true)"
  [ -z "$hits" ] || die "秘密情報らしきファイルがコミット対象に含まれています。中断しました:
${hits}

.gitignoreの除外設定（/.* など）が効いているか確認してください。"
}

# --- ここからs1/s2/s3共通 ---
# 配布リポジトリのルートにはISUCON運営配布のアプリコード（webapp/等）が既に
# 展開された状態で置かれている（非空）。git cloneは非空ディレクトリを拒否するため
# 使えず、代わりにgit init + fetch + checkoutでチームリポジトリの内容
# （Makefile・scripts・tool-config・.claude等）を被せる。

setup_git_remote

echo "チームリポジトリ (${REPO_SSH_URL}) からmainを取得します..."
git fetch origin main
git checkout -f -B main origin/main

# ツール導入・ディレクトリ準備・サーバー設定取得
# （env.sh作成 → make setup → make set-as-<role> → make get-conf）
# </dev/null: このスクリプト自体がstdin経由で流れているため、stdinを読みうる
# 子プロセス（apt-get等）に残りのスクリプトを横取りさせない
sh server-setup.sh "$ROLE" </dev/null

if [ "$ROLE" = "s1" ]; then
  # 配布アプリコードはまだ未追跡なので、ここでチームリポジトリに取り込む。
  # get-confの結果（s1/etc/配下）もこのコミットに含まれる。
  exclude_large_files
  git add -A
  assert_no_secrets_staged

  if git diff --cached --quiet; then
    echo "コミット対象の変更がないため、コミットをスキップします。"
  else
    git commit -m "chore: import distributed application code from s1"
  fi

  if ! git push -u origin main; then
    die "git pushに失敗しました。
origin/mainが他から進んでいる場合は 'git pull --rebase' してから再実行してください。"
  fi
fi

echo "サーバー側のセットアップが完了しました（role: ${ROLE}）。"
