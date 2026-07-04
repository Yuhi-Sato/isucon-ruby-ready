#!/bin/bash

# ローカル実行専用スクリプト。
# チームリポジトリの作成（gh CLI）・サーバーごとのDeploy key自動生成/登録・
# tarball展開・server-setup.shの実行・git初期化/初回push（s1）またはgit配線（s2/s3）
# までを1コマンドで行う。
#
# GitHub認証はサーバー上に生成するDeploy key（対象リポジトリ限定・書き込み可）で行う。
# 旧方式（ssh -A によるagent forwardingでローカル認証を借用）は、sudoでの
# ユーザー切り替えでSSH_AUTH_SOCKが失われる等実運用で不安定なうえ、サーバー上の
# `git pull`（make deploy / make bench の先頭）がforwarding無しでは動かないため廃止した。

set -euo pipefail

REPO_OWNER="Yuhi-Sato"
DEFAULT_TARGET_DIR="/home/isucon"

usage() {
  echo "Usage: $0 <user@server> [repo-name] [--dir <path>] [--role <s1|s2|s3>]" >&2
  echo "  s1  : repo-name省略可（新規採番）。tarball展開からリポジトリ初回pushまで行う" >&2
  echo "  s2/s3: repo-name必須（s1が作成したチームリポジトリ名）。gitでの取得とセットアップを行う" >&2
  echo "  --dir : サーバー上の配布リポジトリルート（webapp/と同階層）。省略時は ${DEFAULT_TARGET_DIR}" >&2
  echo "  --role: <user@server>から役割(s1/s2/s3)を推定できない場合に明示する" >&2
  echo "  前提: ローカルで 'gh auth login' 済みであること（全役割で必要。Deploy key登録に使う）" >&2
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

# Deploy keyはGitHub全体で1つのリポジトリにしか登録できないため、リポジトリ名を
# 含むファイル名で競技（リポジトリ）ごとに別鍵を生成し、鍵の使い回し衝突を防ぐ。
KEY_BASENAME="github_deploy_${REPO_NAME}"

echo "サーバー: ${SERVER} / 役割: ${ROLE} / リポジトリ: ${REPO_SLUG} / 配布repoルート: ${TARGET_DIR}"
if [ "$ROLE" = "s1" ] && [ -z "$REPO_NAME_ARG" ]; then
  echo "（repo-name省略のため上記の名前を新規採番。2台目以降や再実行では明示的に指定すること）"
fi

# --- ローカル側の前提チェック ---
# Deploy keyの登録に使うため、gh CLIは全役割で必須。

if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh CLIが見つかりません。https://cli.github.com/ からインストールしてください。" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "エラー: gh CLIが未認証です。'gh auth login' を実行してから再実行してください。" >&2
  exit 1
fi

# --- リポジトリの作成（s1）/ 存在確認（s2/s3） ---

if [ "$ROLE" = "s1" ]; then
  if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
    echo "リポジトリ ${REPO_SLUG} は既に存在します。"
  else
    echo "リポジトリ ${REPO_SLUG} が見つからないため、gh repo create で新規作成します（private）..."
    gh repo create "$REPO_SLUG" --private
  fi
else
  if ! gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
    echo "エラー: リポジトリ ${REPO_SLUG} が見つかりません。先に './setup.sh s1 ${REPO_NAME}' を実行してください。" >&2
    exit 1
  fi
fi

# --- Deploy keyの生成（サーバー上）と登録（ローカルのgh CLI） ---

echo "サーバー ${SERVER} 上でDeploy keyを準備します..."

# -o RemoteCommand=none: ~/.ssh/configでそのHostにRemoteCommandが設定されていると
# 「コマンドライン上のコマンド」との併用をsshが拒否するため明示的に無効化する。
PUB_KEY="$(ssh -o RemoteCommand=none "$SERVER" bash -s -- "$KEY_BASENAME" "$ROLE" <<'KEYGEN_SCRIPT'
set -euo pipefail
KEY_BASENAME="$1"
ROLE="$2"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
KEY_FILE="$HOME/.ssh/$KEY_BASENAME"
if [ ! -f "$KEY_FILE" ]; then
  # </dev/null: このスクリプト自体がヒアドキュメント経由でbashのstdinに流れているため、
  # stdinを読みうる子プロセスには明示的に切って残りのスクリプトの横取りを防ぐ
  ssh-keygen -q -t ed25519 -N "" -f "$KEY_FILE" -C "${ROLE}-${KEY_BASENAME}" </dev/null
fi
cat "$KEY_FILE.pub"
KEYGEN_SCRIPT
)"

if ! echo "$PUB_KEY" | grep -q "^ssh-ed25519 "; then
  echo "エラー: サーバー上でのDeploy key生成に失敗しました。" >&2
  echo "$PUB_KEY" >&2
  exit 1
fi

PUB_TMP="$(mktemp)"
trap 'rm -f "$PUB_TMP"' EXIT
printf '%s\n' "$PUB_KEY" > "$PUB_TMP"

if ADD_ERR="$(gh repo deploy-key add "$PUB_TMP" --repo "$REPO_SLUG" --allow-write --title "$ROLE" 2>&1)"; then
  echo "Deploy key（${ROLE}）を ${REPO_SLUG} に登録しました。"
else
  # 再実行時は登録済みエラーになるためスキップ扱いにする（冪等）
  if echo "$ADD_ERR" | grep -qi "already in use"; then
    echo "Deploy keyは登録済みのためスキップします。"
  else
    echo "エラー: Deploy keyの登録に失敗しました。" >&2
    echo "$ADD_ERR" >&2
    exit 1
  fi
fi

# --- サーバー側処理（1回のSSH接続に集約する） ---

echo "サーバー ${SERVER} 上でセットアップを行います..."

# ここではローカルの変数をヒアドキュメント内で展開させず、
# bash -s -- の位置引数としてサーバー側スクリプトへ渡す。
ssh -o RemoteCommand=none "$SERVER" bash -s -- "$TARGET_DIR" "$REPO_SSH_URL" "$ROLE" "$KEY_BASENAME" <<'REMOTE_SCRIPT'
set -euo pipefail

TARGET_DIR="$1"
REPO_SSH_URL="$2"
ROLE="$3"
KEY_BASENAME="$4"
KEY_FILE="$HOME/.ssh/$KEY_BASENAME"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"

# このリポジトリ専用のDeploy keyだけを使う（agentや他の鍵に依存しない）
GIT_SSH_CMD="ssh -i $KEY_FILE -o IdentitiesOnly=yes"
export GIT_SSH_COMMAND="$GIT_SSH_CMD"

# github.comのホストキーがknown_hostsになければssh-keyscanで追加する
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! ssh-keygen -F github.com -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "github.comのホストキーが未登録のため追加します..."
  ssh-keyscan -H github.com >> "$KNOWN_HOSTS" 2>/dev/null
fi

# Deploy keyでのGitHub認証疎通確認
# </dev/null必須: このssh -Tはbash -s --（ヒアドキュメント経由でこのスクリプト自体を
# 読み込み中）の子プロセスであり、stdinを明示的に切らないとヒアドキュメントの残り
# （この行より後の全行）を横取りしてしまう。横取りされるとbash側は次の読み出しで
# 即EOFとなり、エラーも出さずここでスクリプトが静かに終了する。
AUTH_CHECK="$(ssh -i "$KEY_FILE" -o IdentitiesOnly=yes -T git@github.com </dev/null 2>&1 || true)"
if ! echo "$AUTH_CHECK" | grep -q "successfully authenticated"; then
  echo "エラー: Deploy keyでのGitHubへのSSH認証に失敗しました。" >&2
  echo "Deploy keyがリポジトリに登録されているか（setup.shの直前の出力）を確認してください。" >&2
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

  # 以後の git pull / push（make deploy / make bench 含む）が追加設定なしで
  # このDeploy keyを使うよう、リポジトリ設定に固定する
  git config core.sshCommand "$GIT_SSH_CMD"

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

  # 以後の git pull / push（make deploy / make bench 含む）が追加設定なしで
  # このDeploy keyを使うよう、リポジトリ設定に固定する
  git config core.sshCommand "$GIT_SSH_CMD"

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
