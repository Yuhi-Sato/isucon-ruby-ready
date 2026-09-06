# shellcheck shell=bash
# shellcheck disable=SC2034  # 変数はsource元の各スクリプトで使われる
# 共通変数定義。scripts/以下の各スクリプトから source される（単体では実行しない）。
# 問題によって変わる変数はここに集約する。

# SERVER_ID は env.sh 内で定義される（make set-as-s1 等で追記される）
# shellcheck disable=SC1091
if [ -f "$HOME/env.sh" ]; then . "$HOME/env.sh"; fi

# secrets.env はAPIキーなどgit管理に乗せない値を置く場所（make distribute-secrets で配布）。
# env.shと違いsN/配下にも取り込まない＝リポジトリのどこにも内容を残さない
# shellcheck disable=SC1091
if [ -f "$HOME/secrets.env" ]; then . "$HOME/secrets.env"; fi

# ローカルからの `ssh <host> "..."` やControlMaster経由のSSHは非ログイン・非対話シェルのため、
# rbenv/xbuildでインストールしたRubyのPATHが通らないことがある。明示的に通す
export PATH="$HOME/local/ruby/bin:$HOME/.rbenv/shims:$PATH"

# 問題によって変わる変数 ------------------------
ISUCON_USER=isucon
APP_DIR=./webapp/ruby
SERVICE_NAME=isu-ruby
DB_SERVICE_NAME=mysql

DB_PATH=/etc/mysql
NGINX_PATH=/etc/nginx

DB_SLOW_LOG=/var/log/mysql/mysql-slow.log
NGINX_LOG=/var/log/nginx/access.log

NOTIFY_DISCORD_TMPFILE=tmp/notify-discord.txt

# make alp / make slow-query の結果を保存するディレクトリ（tmp/以下なのでgit管理外）
MEASURE_LOG_DIR=tmp/measure

# alp / DuckDB のバイナリ選択に使う（arm環境での素振りにも対応）
ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)

# タイムスタンプ-ブランチ名-コミットハッシュ形式のログファイル名を組み立てる
# 引数: 保存先ディレクトリ名（alp / slow-query など）
# 標準出力: 保存先の完全なファイルパス
measure_log_path() {
  local target="$1"
  local stamp branch hash dir
  stamp=$(date "+%Y%m%d-%H%M%S")
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')
  branch="${branch:-no-git}"
  hash=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
  dir="${MEASURE_LOG_DIR}/${target}"
  mkdir -p "$dir"
  echo "${dir}/${stamp}-${branch}-${hash}.log"
}
