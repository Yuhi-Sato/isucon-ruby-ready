#!/bin/bash

# ローカル実行専用スクリプト。
# サーバーにはGitHub認証情報を一切置かず、ローカルのgh CLI認証とSSH agent
# forwardingだけを使って、tarball展開・server-setup.shの実行・チームリポジトリの
# git初期化/初回push（s1）またはgit配線（s2/s3）までを1コマンドで行う。
# 旧git.sh（サーバー上で実行し、サーバーごとにDeploy keyをGitHubへ登録する方式）の後継。

set -euo pipefail

REPO_OWNER="Yuhi-Sato"
DEFAULT_TARGET_DIR="/home/isucon"

usage() {
  echo "Usage: $0 <user@server> [repo-name] [--dir <path>] [--role <s1|s2|s3>]" >&2
  echo "  s1  : repo-name省略可（新規採番）。tarball展開からリポジトリ初回pushまで行う" >&2
  echo "  s2/s3: repo-name必須（s1が作成したチームリポジトリ名）。gitでの取得とセットアップを行う" >&2
  echo "  --dir : サーバー上の配布リポジトリルート（webapp/と同階層）。省略時は ${DEFAULT_TARGET_DIR}" >&2
  echo "  --role: <user@server>から役割(s1/s2/s3)を推定できない場合に明示する" >&2
  exit 1
}

TARGET_DIR="$DEFAULT_TARGET_DIR"
ROLE=""
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      [ "$#" -ge 2 ] || usage
      TARGET_DIR="$2"
      shift 2
      ;;
    --role)
      [ "$#" -ge 2 ] || usage
      ROLE="$2"
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

if [ "${#POSITIONAL[@]}" -lt 1 ] || [ "${#POSITIONAL[@]}" -gt 2 ]; then
  usage
fi

SERVER="${POSITIONAL[0]}"
REPO_NAME_ARG="${POSITIONAL[1]:-}"

# --- 役割の決定 ---
# --role指定を優先。無指定時はSERVER（~/.ssh/configのHostエイリアス等）自体が
# s1/s2/s3のパターンにマッチするかで推定する。isucon@<IPアドレス>形式など
# 推定できない場合はエラーにし、--roleでの明示を促す。
if [ -n "$ROLE" ]; then
  if ! echo "$ROLE" | grep -qE '^s[1-3]$'; then
    echo "エラー: --role は s1 / s2 / s3 のいずれかで指定してください（指定値: ${ROLE}）" >&2
    exit 1
  fi
elif echo "$SERVER" | grep -qE '^s[1-3]$'; then
  ROLE="$SERVER"
else
  echo "エラー: サーバー指定 (${SERVER}) から役割(s1/s2/s3)を推定できません。--role で明示してください。" >&2
  exit 1
fi

if [ "$ROLE" != "s1" ] && [ -z "$REPO_NAME_ARG" ]; then
  echo "エラー: role=${ROLE} の場合はrepo-nameの指定が必須です（s1が作成したチームリポジトリ名を指定）。" >&2
  usage
fi

REPO_NAME="${REPO_NAME_ARG:-ISUCON-$(date +%Y%m%d%H%M%S)}"
REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
REPO_SSH_URL="git@github.com:${REPO_SLUG}.git"

echo "サーバー: ${SERVER} / 役割: ${ROLE} / リポジトリ: ${REPO_SLUG} / 配布repoルート: ${TARGET_DIR}"
if [ "$ROLE" = "s1" ] && [ -z "$REPO_NAME_ARG" ]; then
  echo "（repo-name省略のため上記の名前を新規採番。2台目以降や再実行では明示的に指定すること）"
fi

# --- ローカル側の前提チェック ---

if ! ssh-add -l >/dev/null 2>&1; then
  echo "ssh-agentに鍵が登録されていないため、ssh-add で登録を試みます..."
  if ! ssh-add; then
    echo "エラー: ssh-add に失敗しました。ssh-agentが起動しているか、鍵のパスフレーズを確認してください。" >&2
    exit 1
  fi
fi

if [ "$ROLE" = "s1" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "エラー: gh CLIが見つかりません。https://cli.github.com/ からインストールしてください。" >&2
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "エラー: gh CLIが未認証です。'gh auth login' を実行してから再実行してください。" >&2
    exit 1
  fi

  # --- リポジトリ作成（既に存在すればスキップ。冪等） ---
  if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
    echo "リポジトリ ${REPO_SLUG} は既に存在します。"
  else
    echo "リポジトリ ${REPO_SLUG} が見つからないため、gh repo create で新規作成します（private）..."
    gh repo create "$REPO_SLUG" --private
  fi
else
  # s2/s3はs1が作成済みのリポジトリに乗る想定。gh認証は必須にしないが、
  # 手元にあれば存在確認だけ行い、s1未実行の事故を早期に検出する。
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if ! gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
      echo "エラー: リポジトリ ${REPO_SLUG} が見つかりません。先に './setup.sh s1 ${REPO_NAME}' を実行してください。" >&2
      exit 1
    fi
  fi
fi

# --- サーバー側処理（ssh -A で1回のSSH接続に集約する） ---

echo "サーバー ${SERVER} 上でセットアップを行います..."

# ここではローカルの変数をヒアドキュメント内で展開させず、
# bash -s -- の位置引数としてサーバー側スクリプトへ渡す。
# -o RemoteCommand=none: ~/.ssh/configでそのHostにRemoteCommandが設定されていると
# 「コマンドライン上のコマンド」との併用をsshが拒否する（Cannot execute command-line
# and remote command.）ため、コマンドライン指定を優先させるために明示的に無効化する。
ssh -A -o RemoteCommand=none "$SERVER" bash -s -- "$TARGET_DIR" "$REPO_SSH_URL" "$ROLE" <<'REMOTE_SCRIPT'
set -euo pipefail

TARGET_DIR="$1"
REPO_SSH_URL="$2"
ROLE="$3"
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

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

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

  git add .
  if git diff --cached --quiet; then
    echo "コミット対象の変更がないため、コミットをスキップします。"
  else
    git commit -m 'first commit'
  fi

  if ! git push -u origin main; then
    echo "エラー: git pushに失敗しました。" >&2
    echo "ローカルのssh-agentに鍵が登録された状態でssh -A接続しているか、" >&2
    echo "リポジトリへの書き込み権限（gh CLIの認証ユーザー）があるかを確認してから再実行してください。" >&2
    exit 1
  fi
else
  # s2/s3: TARGET_DIRにはISUCON運営配布のアプリコード（webapp/等）が既に
  # 展開された状態で置かれている（非空）。git cloneは非空ディレクトリを
  # 拒否するため使えず、代わりにgit init + fetch + checkoutでチーム
  # リポジトリの内容（Makefile・tool-config・webapp含む）を被せる。
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

  echo "チームリポジトリ (${REPO_SSH_URL}) からmainを取得します..."
  git fetch origin main
  git checkout -f -B main origin/main

  # ツール導入・ディレクトリ準備・サーバー設定取得（env.sh作成 → make setup →
  # make set-as-s2/s3 → make get-conf）。
  sh server-setup.sh "$ROLE"
fi

echo "サーバー側のセットアップが完了しました（role: ${ROLE}）。"
REMOTE_SCRIPT

echo "setup.shが完了しました: ${SERVER}:${TARGET_DIR} -> ${REPO_SSH_URL} (role: ${ROLE})"
