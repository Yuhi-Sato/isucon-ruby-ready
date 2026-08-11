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
	./scripts/setup.sh $*

.PHONY: setup
setup: ## （誤り防止）setup-s1 / setup-s2 / setup-s3 を使う
	@echo "usage: make setup-s1 (or setup-s2 / setup-s3)" >&2; exit 1

.PHONY: install-tools
install-tools: ## 解析ツール（alp / notify_slack / DuckDB等）をインストールする
	./scripts/install-tools.sh

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

.PHONY: bench-prep
bench-prep: ## ベンチ実行直前の準備（ログ削除・設定反映・DB/nginx含む全再起動。ベンチ自体は実行しない）
	./scripts/bench-prep.sh

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
