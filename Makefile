# ローカルからのリモート操作用（Host s1/s2/s3 は ~/.ssh/config に手書き。README参照）
# 配布リポジトリのルートが /home/isucon 以外なら REMOTE_DEPLOY_PATH で上書きする。
REMOTE_DEPLOY_PATH ?= /home/isucon
SERVERS := s1 s2 s3

# scripts/vars.sh や env.sh をレシピ内で source するため、シェルを明示する（dashではなくbash）
SHELL := /bin/bash

# 引数なしのmakeで setup が走らないように、デフォルトはヘルプ表示にする
.DEFAULT_GOAL := help

# パターンルール（extract-% など）は .PHONY を指定できず、同名ファイルが存在すると
# "up to date" 扱いでレシピが黙ってスキップされる。FORCE を前提に付けて必ず実行させる
FORCE:

.PHONY: help
help: ## ターゲット一覧を表示する
	@grep -hE '^[a-zA-Z0-9_%-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

# セットアップ ------------------------

# setup-s1 / setup-s2 / setup-s3
setup-%: FORCE ## サーバーの環境構築（setup-s1 など）。ツール・SERVER_ID・初回commit
	@echo "$*" | grep -qE '^s[1-3]$$' || { echo "usage: make setup-s1 (or setup-s2 / setup-s3)" >&2; exit 1; }
	$(MAKE) install-tools
	mkdir -p tool-config/alp tool-config/slow-query tool-config/nginx
# SERVER_ID をセット（get-conf / deploy-conf の前提）。commit 前に走らせて sN/ を初回pushに含める
	$(MAKE) set-as-$*
# サーバー上のgit identity。ここで作られるコミットはs1の「配布コード取り込み」だけなので
# 厳密である必要はない。既に設定済みなら尊重し、未設定のときだけ中立な値を入れる。
	git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "isucon"
	git config --global user.email >/dev/null 2>&1 || git config --global user.email "isucon@localhost"
	git add .
	git commit -m "chore: setup ($*)"
	git push origin main

.PHONY: setup
setup: ## （誤り防止）setup-s1 / setup-s2 / setup-s3 を使う
	@echo "usage: make setup-s1 (or setup-s2 / setup-s3)" >&2; exit 1

.PHONY: install-tools
install-tools: ## 解析ツール（alp / DuckDB等）をインストールする
	./scripts/install-tools.sh

.PHONY: self-signed-cert
self-signed-cert: ## 練習用の自己署名証明書を作成する（CERT_HOST=<ホスト名またはIP>、再作成は FORCE=1）
	@test -n "$(CERT_HOST)" || { echo "usage: make self-signed-cert CERT_HOST=<hostname-or-ip> [FORCE=1]" >&2; exit 1; }
	./scripts/create-self-signed-cert.sh $(if $(filter 1,$(FORCE)),--force) "$(CERT_HOST)"

# set-as-s1 / set-as-s2 / set-as-s3（役割の付け直し用。初回は setup-sN に含まれる）
set-as-%: FORCE ## このサーバーをs1/s2/s3として設定する（set-as-s1 など）
	./scripts/set-as.sh $*

.PHONY: check-server-id
check-server-id: ## SERVER_IDが設定されているか確認する
	@./scripts/check-server-id.sh

# 設定ファイルの取得・反映 ------------------------

.PHONY: get-conf
get-conf: ## 設定ファイルなどを取得してgit管理下に配置する
	./scripts/get-conf.sh

.PHONY: deploy-conf
deploy-conf: ## リポジトリ内の設定ファイルをそれぞれ配置する
	./scripts/deploy-conf.sh

# デプロイ・ベンチ ------------------------

.PHONY: deploy
deploy: ## サーバー上の軽量デプロイ（git pull→bundle install→アプリ再起動。ログは消さない・DB/nginxは触らない）
	git pull
	$(MAKE) check-server-id
	. scripts/vars.sh && cd "$$APP_DIR" && bundle install
	$(MAKE) restart-app

.PHONY: bench-prep
bench-prep: ## ベンチ実行直前の準備（ログ削除・設定反映・DB/nginx含む全再起動。ベンチ自体は実行しない）
	git pull
# 各ステップは $(MAKE) で呼ぶ。子makeがpull後のMakefile・スクリプトを読み直すので、
# 常に最新版のレシピで実行される
	$(MAKE) check-server-id
	. scripts/vars.sh && cd "$$APP_DIR" && bundle install
	$(MAKE) rm-logs
	$(MAKE) deploy-conf
	$(MAKE) restart

# ssh先で実行するコマンドの前置き。REMOTE_DEPLOY_PATH に空白が含まれても壊れないよう単引用符で囲む
REMOTE_CD := cd '$(REMOTE_DEPLOY_PATH)'
# typoしたホスト名にそのままsshしないよう、各ターゲットの先頭で s1/s2/s3 かを検査する

# 注意: remote-deploy-% は remote-deploy-conf-s1 にもマッチするため、より具体的なルールを先に書く
# remote-deploy-conf-s1 / ...
remote-deploy-conf-%: FORCE ## ローカルから対象サーバーへ設定反映+全再起動する（remote-deploy-conf-s1 など）
	@echo "$*" | grep -qE '^s[1-3]$$' || { echo "unknown host: $* (expected s1 / s2 / s3)" >&2; exit 1; }
	ssh "$*" "$(REMOTE_CD) && git pull && make deploy-conf && make restart"

# remote-bench-prep-s1 / ...
remote-bench-prep-%: FORCE ## ローカルから対象サーバーで bench-prep する（remote-bench-prep-s1 など）
	@echo "$*" | grep -qE '^s[1-3]$$' || { echo "unknown host: $* (expected s1 / s2 / s3)" >&2; exit 1; }
# git pull は bench-prep 側の先頭で行う
	ssh "$*" "$(REMOTE_CD) && make bench-prep"

# remote-deploy-s1 / remote-deploy-s2 / remote-deploy-s3
remote-deploy-%: FORCE ## ローカルから対象サーバーへ軽量デプロイする（remote-deploy-s1 など）
	@echo "$*" | grep -qE '^s[1-3]$$' || { echo "unknown host: $* (expected s1 / s2 / s3)" >&2; exit 1; }
	ssh "$*" "$(REMOTE_CD) && make deploy"

# -k: 失敗したサーバーがあっても残りへ続行し、最後にまとめて失敗を報告して非0で終了する
# -j: 全サーバーへ並列デプロイする（出力は交錯する）
.PHONY: remote-deploy-all
remote-deploy-all: ## ローカルから全サーバーへ並列で軽量デプロイする（対象は SERVERS で調整）
	$(MAKE) -k -j $(words $(SERVERS)) $(addprefix remote-deploy-,$(SERVERS))

.PHONY: restart
restart: ## DB・アプリ・nginxをすべて再起動する
	./scripts/restart.sh all

.PHONY: restart-app
restart-app: ## アプリのみ再起動する（自動デプロイ用。DB/nginxは触らない）
	./scripts/restart.sh app

.PHONY: rm-logs
rm-logs: ## アクセスログ・スロークエリログ・クエリダイジェスト統計を空にする
	./scripts/rm-logs.sh

# 計測・解析 ------------------------

.PHONY: alp
alp: ## alpでアクセスログを確認する
	@./scripts/alp.sh

.PHONY: slow-query
slow-query: ## performance_schemaのクエリダイジェスト集計を表示する
	@./scripts/slow-query.sh

.PHONY: nd
nd: notify-discord-alp notify-discord-slow-query ## alp / slow-query の結果をDiscordに通知する

# notify-discord-alp / notify-discord-slow-query
notify-discord-%: FORCE ## alp / slow-query の結果をDiscordに通知する（notify-discord-alp など）
	./scripts/notify-discord.sh $*

# duckdb-flow / duckdb-repeat / duckdb-heavy-users
duckdb-%: FORCE ## ユーザー行動履歴の定型分析（duckdb-flow / duckdb-repeat / duckdb-heavy-users）
	@./scripts/duckdb.sh $*

.PHONY: watch-service-log
watch-service-log: ## アプリケーションのログを確認する
	./scripts/watch-service-log.sh

.PHONY: vernier-view
vernier-view: ## 直近のVernierプロファイル（Markdown形式）を表示する（tmp/vernier以下に出力する想定）
	@./scripts/vernier-view.sh

.PHONY: add-profiling-gems
add-profiling-gems: ## Vernier用gemを追加する（ローカル専用。詳細はREADME参照）
	./scripts/add-profiling-gems.sh
