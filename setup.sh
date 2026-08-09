#!/bin/bash

# ローカル実行専用スクリプト。
# チームリポジトリの作成（gh CLI）・サーバーごとのDeploy key自動生成/登録・
# tarball展開・server-setup.shの実行・git初期化/初回push（s1）またはgit配線（s2/s3）
# までを1コマンドで行う。
#
# GitHub認証はサーバー上に生成するDeploy key（対象リポジトリ限定・書き込み可）で行う。
# 旧方式（ssh -A によるagent forwardingでローカル認証を借用）は、sudoでの
# ユーザー切り替えでSSH_AUTH_SOCKが失われる等実運用で不安定なうえ、サーバー上の
# `git pull`（make deploy / make bench-prep の先頭）がforwarding無しでは動かないため廃止した。

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

# --- サーバー側処理の実行ユーザーの決定 ---
# 練習環境等ではSSH接続ユーザーがisuconでない（ubuntu等の管理ユーザー）ことがある。
# そのままでは/home/isuconへのtar展開が権限エラーになり、Deploy keyも接続ユーザーの
# homeに作られてisuconのgit操作と噛み合わない。接続ユーザーがisuconでなければ、
# サーバー側処理（鍵生成・remote-setup.sh）全体をsudoでisuconとして実行する。
# -n: パスワードが必要ならプロンプトで固まらず即失敗させる（passwordless sudo前提）
# -H: $HOMEをisuconのものにする。-i（ログインシェル）は使わない。.profile等の
#     出力が後続のpubkeyキャプチャを汚染しうるため。
REMOTE_USER="$(ssh -o RemoteCommand=none "$SERVER" whoami)"
REMOTE_BASH=(bash -s)
if [ "$REMOTE_USER" != "isucon" ]; then
  echo "SSH接続ユーザーが ${REMOTE_USER} のため、サーバー側処理は sudo -u isucon で実行します。"
  REMOTE_BASH=(sudo -n -u isucon -H bash -s)
fi

# --- Deploy keyの生成（サーバー上）と登録（ローカルのgh CLI） ---

echo "サーバー ${SERVER} 上でDeploy keyを準備します..."

# -o RemoteCommand=none: ~/.ssh/configでそのHostにRemoteCommandが設定されていると
# 「コマンドライン上のコマンド」との併用をsshが拒否するため明示的に無効化する。
PUB_KEY_RAW="$(ssh -o RemoteCommand=none "$SERVER" "${REMOTE_BASH[@]}" -- "$KEY_BASENAME" "$ROLE" <<'KEYGEN_SCRIPT'
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

# sudo経由等で余計な出力が混ざる可能性に備え、公開鍵の行だけを取り出す
PUB_KEY="$(echo "$PUB_KEY_RAW" | grep '^ssh-ed25519 ' | tail -n 1 || true)"

if [ -z "$PUB_KEY" ]; then
  echo "エラー: サーバー上でのDeploy key生成に失敗しました。" >&2
  echo "$PUB_KEY_RAW" >&2
  echo "（sudoのパスワードが要求される環境の場合は、READMEのフォールバック手順でremote-setup.shを直接実行してください）" >&2
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

# --- サーバー側処理（remote-setup.shを流し込んで実行する） ---
# 中身はremote-setup.sh参照。サーバー上で単体実行して再開することもできる。

echo "サーバー ${SERVER} 上でセットアップを行います..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ssh -o RemoteCommand=none "$SERVER" "${REMOTE_BASH[@]}" -- "$ROLE" "$REPO_NAME" --dir "$TARGET_DIR" \
  < "$SCRIPT_DIR/remote-setup.sh"

echo "setup.shが完了しました: ${SERVER}:${TARGET_DIR} -> ${REPO_SSH_URL} (role: ${ROLE})"
