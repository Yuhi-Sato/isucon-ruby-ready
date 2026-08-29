# shellcheck shell=bash
# shellcheck disable=SC2034  # 変数はsource元の各スクリプトで使われる
# 共通変数定義。scripts/以下の各スクリプトから source される（単体では実行しない）。
# 問題によって変わる変数はここに集約する（isucon-initial-recon スキル参照）。

# SERVER_ID は env.sh 内で定義される（make set-as-s1 等で追記される）
# shellcheck disable=SC1091
if [ -f "$HOME/env.sh" ]; then . "$HOME/env.sh"; fi

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

# alp / DuckDB のバイナリ選択に使う（arm環境での素振りにも対応）
ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
