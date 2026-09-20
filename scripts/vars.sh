# shellcheck shell=bash
# shellcheck disable=SC2034  # 変数はsource元の各スクリプトで使われる
# 共通変数定義。scripts/以下の各スクリプトから source される（単体では実行しない）。
# 問題によって変わる変数はここに集約する。

# SERVER_ID は env.sh 内で定義される（setup.shから追記される）
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

# make alp / make slow-query の結果を保存するディレクトリ。
# tmp/ とは別にして、実行結果をgit管理下に置き履歴として残す（ベンチ結果の推移をコミット単位で追える）
MEASURE_LOG_DIR=measure-logs

# alp のバイナリ選択に使う（arm環境での素振りにも対応）
ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)

# 計測ログのタイムスタンプ・ブランチ名・コミットハッシュを算出し、
# MEASURE_STAMP / MEASURE_BRANCH / MEASURE_HASH にセットする。
# measure_log_path / measure_log_header で同じ値を使うため、呼び出し側で最初に一度だけ呼ぶ
measure_log_meta() {
  MEASURE_STAMP=$(date "+%Y%m%d-%H%M%S")
  MEASURE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')
  MEASURE_BRANCH="${MEASURE_BRANCH:-no-git}"
  MEASURE_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
}

# タイムスタンプ-ブランチ名-コミットハッシュ形式のログファイル名を組み立てる（事前に measure_log_meta が必要）
# 引数: 保存先ディレクトリ名（alp / slow-query など）
# 標準出力: 保存先の完全なファイルパス
measure_log_path() {
  local target="$1"
  local dir="${MEASURE_LOG_DIR}/${target}"
  mkdir -p "$dir"
  echo "${dir}/${MEASURE_STAMP}-${MEASURE_BRANCH}-${MEASURE_HASH}.log"
}

# ログファイル名だけでなく中身にもタイムスタンプ・ブランチ・コミットハッシュを残すためのヘッダー
# （ファイルが移動・リネームされても計測条件が追えるように。事前に measure_log_meta が必要）
# 標準出力: ヘッダー行（# コメント形式）
measure_log_header() {
  cat <<HEADER
# timestamp: ${MEASURE_STAMP}
# branch: ${MEASURE_BRANCH}
# commit: ${MEASURE_HASH}
HEADER
}
