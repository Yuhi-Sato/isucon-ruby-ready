#!/bin/bash
# 競技当日に配られた秘密鍵とサーバーIPから、SSH接続設定をこのリポジトリの ssh/ 配下に生成する。
# ローカルマシン専用（サーバー上では実行しない）。冪等なので、IPや鍵が変わったら同じコマンドで再実行して上書きする。
#
# Usage: ./ssh-setup.sh --key <秘密鍵パス> [--user <接続ユーザー>] <ip1> [ip2] [ip3]
# 例:    ./ssh-setup.sh --key ~/Downloads/isucon.pem 203.0.113.1 203.0.113.2 203.0.113.3
#        ./ssh-setup.sh --key ~/Downloads/my_key.pem --user ubuntu 203.0.113.1   # 練習EC2
set -eu
cd "$(dirname "$0")"
REPO_ROOT=$(pwd)

usage() {
  cat >&2 <<'EOF'
Usage: ./ssh-setup.sh --key <秘密鍵パス> [--user <接続ユーザー>] <ip1> [ip2] [ip3]
  --key   配られた秘密鍵のパス（ssh/keys/ にコピーされる）
  --user  SSH接続ユーザー（省略時: isucon。練習EC2では ubuntu 等を指定）
  ipN     サーバーのグローバルIP。渡した順に Host s1 / s2 / s3 になる
EOF
  exit 1
}

KEY_SRC=""
SSH_USER=isucon
IPS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --key)  KEY_SRC="${2:?--key の値が空}"; shift 2 ;;
    --user) SSH_USER="${2:?--user の値が空}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "エラー: 不明なオプション: $1" >&2; usage ;;
    *)  IPS+=("$1"); shift ;;
  esac
done

if [ -z "$KEY_SRC" ]; then echo "エラー: --key は必須" >&2; usage; fi
if [ ! -f "$KEY_SRC" ]; then echo "エラー: 秘密鍵が見つからない: $KEY_SRC" >&2; exit 1; fi
if [ "${#IPS[@]}" -lt 1 ] || [ "${#IPS[@]}" -gt 3 ]; then echo "エラー: IPは1〜3個指定する" >&2; usage; fi

# 鍵を ssh/keys/ に取り込む（配布元のパーミッションに関わらず600にする）
mkdir -p "$REPO_ROOT/ssh/keys"
KEY_DEST="$REPO_ROOT/ssh/keys/$(basename "$KEY_SRC")"
cp "$KEY_SRC" "$KEY_DEST"
chmod 600 "$KEY_DEST"

# ssh/config を全体再生成する。sshのIdentityFile等の相対パスはconfigの場所ではなく
# CWD基準で解決されるため、必ず絶対パスで埋め込む
CONFIG="$REPO_ROOT/ssh/config"
{
  echo "# ssh-setup.sh が生成するファイル。手で編集せず、IP/鍵が変わったら再実行する"
  i=0
  for ip in "${IPS[@]}"; do
    i=$((i + 1))
    cat <<EOF

Host s$i
  HostName $ip
  User $SSH_USER
  IdentityFile $KEY_DEST
  StrictHostKeyChecking accept-new
  UserKnownHostsFile $REPO_ROOT/ssh/known_hosts
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
EOF
  done
} > "$CONFIG"

# ControlPath用のソケットディレクトリ
mkdir -p "$HOME/.ssh/sockets"
chmod 700 "$HOME/.ssh"

# ~/.ssh/config の先頭にマーカー付きIncludeブロックを冪等に挿入する。
# sshは各オプションについて最初に見つけた値を採用するため、先頭に置くことで
# 過去の競技で書いた Host s1 等の残骸設定よりこのリポジトリの設定が優先される
USER_CONFIG="$HOME/.ssh/config"
MARK_BEGIN="# >>> isucon-ruby-ready >>>"
MARK_END="# <<< isucon-ruby-ready <<<"
touch "$USER_CONFIG"
TMP=$(mktemp)
{
  echo "$MARK_BEGIN"
  echo "Include $CONFIG"
  echo "$MARK_END"
  # 既存のマーカーブロックを取り除いた残りを続ける（再実行時の重複防止）
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$USER_CONFIG"
} > "$TMP"
mv "$TMP" "$USER_CONFIG"
chmod 600 "$USER_CONFIG"

echo "生成完了: $CONFIG"
if ! command -v ssh >/dev/null 2>&1; then
  echo "警告: sshコマンドが見つからないため解決結果の確認をスキップした" >&2
  exit 0
fi
echo "---- 接続設定の解決結果（ssh -G） ----"
n=0
for _ in "${IPS[@]}"; do
  n=$((n + 1))
  echo "[s$n]"
  ssh -G "s$n" | grep -E '^(hostname|user|identityfile) ' | sed 's/^/  /'
done
echo "--------------------------------------"
echo "ssh s1 'hostname' などで接続できることを確認してください"
