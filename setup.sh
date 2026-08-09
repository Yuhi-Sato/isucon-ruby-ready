#!/bin/bash

# ローカル実行専用スクリプト。
# servers.conf に書いたアドレスと鍵をもとに、~/.ssh/config の生成・サーバー側の
# セットアップ・配布コードのチームリポジトリへのpushまでを1コマンドで行う。
#
# 前提: このリポジトリはGitHubのテンプレートリポジトリとして使う。
#   gh repo create <name> --template Yuhi-Sato/isucon-ruby-ready --private --clone
# で作ったチームリポジトリのclone内から実行する。リポジトリの作成はsetup.shの
# 責務ではなく、pushする先はoriginから判別する。
#
# GitHub認証はssh agent forwardingで行う。ローカルのssh-agentに載せた鍵を
# サーバーへ転送し、サーバー上のgitはそれを使う。サーバー上に鍵は作らない。
# 転送設定(ForwardAgent yes)は~/.ssh/configの管理ブロックに書き込むため、
# セットアップ後の `make deploy` / `make bench-prep` の `git pull` も動く。

set -euo pipefail

UPSTREAM_TEMPLATE="Yuhi-Sato/isucon-ruby-ready"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$SCRIPT_DIR/servers.conf"

SSH_CONFIG="$HOME/.ssh/config"
SSH_BLOCK_BEGIN="# >>> isucon-ruby-ready managed block >>>"
SSH_BLOCK_END="# <<< isucon-ruby-ready managed block <<<"

die() { echo "エラー: $*" >&2; exit 1; }
warn() { echo "警告: $*" >&2; }

usage() {
  cat >&2 <<'USAGE'
Usage: ./setup.sh [s1|s2|s3] [--dir <path>]

  引数なし  : s1 をセットアップする
  s2 / s3   : 2台目以降をセットアップする（s1のセットアップ完了後に実行すること）
  --dir     : servers.conf の REMOTE_DIR を上書きする

  前提: このリポジトリをテンプレートとして作ったチームリポジトリのclone内で実行する。
        接続情報は servers.conf に書く（servers.conf.example をコピーして作る）。
USAGE
  exit 1
}

# "~/path" をホームディレクトリに展開する。servers.conf では $HOME を推奨しているが、
# ~ で書かれてもシェルのチルダ展開は効かない（クォート内・変数代入後のため）ので補う。
expand_tilde() {
  case "$1" in
    "~/"*) printf '%s\n' "${HOME}/${1#\~/}" ;;
    *)     printf '%s\n' "$1" ;;
  esac
}

# --- 引数のパース ---

ROLE=""
DIR_OVERRIDE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      [ "$#" -ge 2 ] || usage
      DIR_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    s1|s2|s3)
      [ -z "$ROLE" ] || usage
      ROLE="$1"
      shift
      ;;
    *)
      echo "不明な引数: $1" >&2
      usage
      ;;
  esac
done

ROLE="${ROLE:-s1}"

# --- チームリポジトリの特定（originから導出する） ---

ORIGIN_URL="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
[ -n "$ORIGIN_URL" ] || die "originリモートが見つかりません。
'gh repo create <name> --template ${UPSTREAM_TEMPLATE} --private --clone' で作った
チームリポジトリのclone内でこのスクリプトを実行してください。"

# git@github.com:o/r.git / https://github.com/o/r.git / ssh://git@github.com/o/r
# のいずれも o/r になる
REPO="$(printf '%s\n' "$ORIGIN_URL" | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##')"

case "$REPO" in
  */*/*|*/|/*) die "originから owner/repo を取り出せません: ${ORIGIN_URL}" ;;
  */*) : ;;
  *) die "originがGitHubのリポジトリではありません: ${ORIGIN_URL}" ;;
esac

if [ "$REPO" = "$UPSTREAM_TEMPLATE" ]; then
  die "originがテンプレート本体(${UPSTREAM_TEMPLATE})のままです。
テンプレートを直接cloneするのではなく、テンプレートから作ったチームリポジトリの中で実行してください。
  gh repo create <name> --template ${UPSTREAM_TEMPLATE} --private --clone"
fi

REPO_SSH_URL="git@github.com:${REPO}.git"

# --- servers.conf の読み込み ---

[ -f "$CONF_FILE" ] || die "${CONF_FILE} がありません。サンプルをコピーして接続情報を記入してください。
  cp servers.conf.example servers.conf"

# shellcheck source=/dev/null
. "$CONF_FILE"

S1_HOST="${S1_HOST:-}"
S2_HOST="${S2_HOST:-}"
S3_HOST="${S3_HOST:-}"
SSH_USER="${SSH_USER:-isucon}"
SSH_KEY="$(expand_tilde "${SSH_KEY:-}")"
REMOTE_DIR="${REMOTE_DIR:-/home/isucon}"
GITHUB_KEY="$(expand_tilde "${GITHUB_KEY:-}")"

TARGET_DIR="${DIR_OVERRIDE:-$REMOTE_DIR}"

role_host() {
  case "$1" in
    s1) printf '%s\n' "$S1_HOST" ;;
    s2) printf '%s\n' "$S2_HOST" ;;
    s3) printf '%s\n' "$S3_HOST" ;;
  esac
}

[ -n "$(role_host "$ROLE")" ] || die "servers.conf の $(echo "$ROLE" | tr '[:lower:]' '[:upper:]')_HOST が空です。対象サーバーのアドレスを記入してください。"

if [ -n "$SSH_KEY" ] && [ ! -f "$SSH_KEY" ]; then
  die "servers.conf の SSH_KEY が指すファイルがありません: ${SSH_KEY}"
fi

echo "リポジトリ: ${REPO} / 役割: ${ROLE} / サーバー: $(role_host "$ROLE") / 配布repoルート: ${TARGET_DIR}"

# --- GitHub認証の確認（サーバーに触る前にローカルで完結させる） ---
# ここが通れば「転送される鍵はGitHubで通る」と確定する。

if ! ssh-add -l >/dev/null 2>&1; then
  [ -n "$GITHUB_KEY" ] || die "ssh-agentに鍵がありません。
GitHubに登録済みの鍵を 'ssh-add <鍵のパス>' で読み込むか、servers.conf の GITHUB_KEY を設定してください。"
  echo "ssh-agentに鍵が無いため ${GITHUB_KEY} を読み込みます..."
  ssh-add "$GITHUB_KEY" || die "ssh-add に失敗しました: ${GITHUB_KEY}"
fi

GH_AUTH_CHECK="$(ssh -o StrictHostKeyChecking=accept-new -T git@github.com </dev/null 2>&1 || true)"
if ! echo "$GH_AUTH_CHECK" | grep -q "successfully authenticated"; then
  die "git@github.com へのSSH認証に失敗しました。転送してもサーバーから通りません。
ssh-agentに載っている鍵がGitHub（Settings > SSH and GPG keys）に登録されているか確認してください。

sshの応答:
${GH_AUTH_CHECK}"
fi
echo "GitHubへのSSH認証を確認しました。"

# --- ~/.ssh/config の管理ブロックを生成する ---
# ssh_configは「最初に得られた値」が勝つため、管理ブロックはファイル先頭に置く。
# 末尾に追記すると、既存の Host * の IdentityFile や ForwardAgent no に負ける。

render_host_block() {
  local role="$1" host="$2"
  cat <<EOF
Host ${role}
  HostName ${host}
  User ${SSH_USER}
EOF
  [ -z "$SSH_KEY" ] || cat <<EOF
  IdentityFile ${SSH_KEY}
  IdentitiesOnly yes
EOF
  # ForwardAgent: サーバー上のgitがローカルのssh-agentを使うための転送設定。
  #   セットアップ時だけでなく、以後の make deploy / bench-prep の git pull も
  #   これに依存するため、コマンドラインの -A ではなくconfigに書く。
  # ControlPath の %h はHostName解決後の値。%n にするとIP変更後に古いmaster接続を掴む。
  cat <<'EOF'
  ForwardAgent yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts_isucon
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600

EOF
}

render_ssh_config() {
  local body rest role host

  mkdir -p "$HOME/.ssh/sockets"
  chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"
  [ -e "$SSH_CONFIG" ] || { : > "$SSH_CONFIG"; chmod 600 "$SSH_CONFIG"; }
  cp -p "$SSH_CONFIG" "${SSH_CONFIG}.isucon-bak"

  body="$(mktemp)"
  rest="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$body' '$rest'" RETURN

  {
    printf '%s\n' "$SSH_BLOCK_BEGIN"
    printf '%s\n' "# setup.sh が servers.conf から自動生成する。手で編集しても次回実行で上書きされる。"
    # 対象ロール以外も、アドレスが埋まっていれば書く（make remote-deploy-s2 等がすぐ使える）
    for role in s1 s2 s3; do
      host="$(role_host "$role")"
      [ -n "$host" ] || continue
      render_host_block "$role" "$host"
    done
    printf '%s\n' "$SSH_BLOCK_END"
  } > "$body"

  # 既存の管理ブロックを取り除く（再実行で重複させない）
  awk -v b="$SSH_BLOCK_BEGIN" -v e="$SSH_BLOCK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$SSH_CONFIG" > "$rest"

  # 管理ブロックの外に Host s1/s2/s3 が残っていると、先に現れた方が勝って
  # 管理ブロックが無視される。消すのは利用者の判断なので警告に留める。
  local dup
  dup="$(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i ~ /^s[1-3]$/) print "  " FNR ": " $0 }' "$rest")"
  if [ -n "$dup" ]; then
    warn "${SSH_CONFIG} の管理ブロック外に Host s1/s2/s3 の定義が残っています。
sshは先に現れた値を採用するため、古い定義が優先されます。不要なら削除してください。"
    printf '%s\n' "$dup" >&2
  fi

  cat "$body" "$rest" > "$SSH_CONFIG"
  echo "${SSH_CONFIG} の管理ブロックを更新しました（退避: ${SSH_CONFIG}.isucon-bak）。"
}

render_ssh_config

# --- サーバー側のログインユーザーを確認する ---
# 以降の処理はすべてisuconとして走る必要がある。かつてはisucon以外でログインした
# 場合に sudo -u isucon で包んでいたが、sudoはSSH_AUTH_SOCKを落とすうえ
# ソケット自体がログインユーザー所有の0600なのでisuconからは読めず、
# agent forwardingと両立しない。
# -o RemoteCommand=none: ~/.ssh/configでそのHostにRemoteCommandが設定されていると
# 「コマンドライン上のコマンド」との併用をsshが拒否するため明示的に無効化する。

REMOTE_USER="$(ssh -o RemoteCommand=none "$ROLE" whoami)"
if [ "$REMOTE_USER" != "isucon" ]; then
  die "サーバーへのログインユーザーが ${REMOTE_USER} です。isuconでログインしてください。
サーバー上で isucon の ~/.ssh/authorized_keys に自分の公開鍵を追加したうえで、
servers.conf の SSH_USER=isucon にして再実行してください。"
fi

# --- サーバー側処理（remote-setup.shを流し込んで実行する） ---
# 中身はremote-setup.sh参照。サーバー上で単体実行して再開することもできる。

echo "サーバー ${ROLE} 上でセットアップを行います..."

ssh -o RemoteCommand=none "$ROLE" \
  "bash -s -- ${ROLE} ${REPO} --dir $(printf '%q' "$TARGET_DIR")" \
  < "$SCRIPT_DIR/remote-setup.sh"

echo ""
echo "setup.shが完了しました: ${ROLE}:${TARGET_DIR} -> ${REPO_SSH_URL}"
if [ "$ROLE" = "s1" ]; then
  echo "サーバーの配布コードがpushされました。ローカルに取り込んでください:"
  echo "  git pull"
fi
