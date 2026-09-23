# ローカルからのリモート操作用（Host s1/s2/s3 は ~/.ssh/config に手書き。README参照）
# 配布リポジトリのルートが /home/isucon 以外なら REMOTE_DEPLOY_PATH で上書きする。
REMOTE_DEPLOY_PATH ?= /home/isucon
SERVERS := s1 s2 s3

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

.PHONY: self-signed-cert
self-signed-cert: ## 練習用の自己署名証明書を作成する（CERT_HOST=<ホスト名またはIP>、再作成は FORCE=1）
	@test -n "$(CERT_HOST)" || { echo "usage: make self-signed-cert CERT_HOST=<hostname-or-ip> [FORCE=1]" >&2; exit 1; }
	./scripts/create-self-signed-cert.sh $(if $(filter 1,$(FORCE)),--force) "$(CERT_HOST)"

# デプロイ・ベンチ ------------------------

.PHONY: deploy
deploy: ## サーバー上の軽量デプロイ（git pull→bundle install→アプリ再起動。ログは消さない・DB/nginxは触らない）
	./scripts/checkout-branch.sh "$(BRANCH)"
	git pull $(if $(BRANCH),origin $(BRANCH),)
	./scripts/deploy.sh

.PHONY: bench-prep
bench-prep: ## ベンチ実行直前の準備（ログ削除・設定反映・DB/nginx含む全再起動。ベンチ自体は実行しない）
	./scripts/bench-prep.sh

# 注意: remote-deploy-% は remote-deploy-conf-s1 にもマッチするため、より具体的なルールを先に書く
# remote-deploy-conf-s1 / ...
remote-deploy-conf-%: FORCE ## ローカルから対象サーバーへ設定反映+全再起動する（remote-deploy-conf-s1 など）
	REMOTE_DEPLOY_PATH=$(REMOTE_DEPLOY_PATH) ./scripts/remote.sh $* deploy-conf "$(BRANCH)"

# remote-bench-prep-s1 / ...
remote-bench-prep-%: FORCE ## ローカルから対象サーバーで bench-prep する（remote-bench-prep-s1 など）
	REMOTE_DEPLOY_PATH=$(REMOTE_DEPLOY_PATH) ./scripts/remote.sh $* bench-prep "$(BRANCH)"

# remote-deploy-s1 / remote-deploy-s2 / remote-deploy-s3
remote-deploy-%: FORCE ## ローカルから対象サーバーへ軽量デプロイする（remote-deploy-s1 など）
	REMOTE_DEPLOY_PATH=$(REMOTE_DEPLOY_PATH) ./scripts/remote.sh $* deploy "$(BRANCH)"

# remote-nd-s1 / remote-nd-s2 / remote-nd-s3
remote-nd-%: FORCE ## ローカルから対象サーバーで make nd する（remote-nd-s1 など）
	REMOTE_DEPLOY_PATH=$(REMOTE_DEPLOY_PATH) ./scripts/remote.sh $* nd

.PHONY: remote-nd
remote-nd: ## ローカルから s1 で make nd する（alp / slow-query 結果をDiscord通知）
	$(MAKE) remote-nd-s1

# 計測ログは各サーバーが同時にpushするが、scripts/push-measure-log.sh が pull --rebase でやり直すので並列で良い
.PHONY: remote-nd-all
remote-nd-all: ## ローカルから全サーバーで並列に make nd する（対象は SERVERS で調整）
	$(MAKE) -k -j $(words $(SERVERS)) $(addprefix remote-nd-,$(SERVERS))

# -k: 失敗したサーバーがあっても残りへ続行し、最後にまとめて失敗を報告して非0で終了する
# -j: 全サーバーへ並列デプロイする（出力は交錯する）
.PHONY: remote-deploy-all
remote-deploy-all: ## ローカルから全サーバーへ並列で軽量デプロイする（対象は SERVERS で調整）
	$(MAKE) -k -j $(words $(SERVERS)) $(addprefix remote-deploy-,$(SERVERS))

.PHONY: distribute-secrets
distribute-secrets: ## ローカルのsecrets.envを全サーバーへSSHで配布する（対象は SERVERS、ファイルは SECRETS_FILE で調整）
	SERVERS="$(SERVERS)" ./scripts/distribute-secrets.sh

# 計測・解析 ------------------------

.PHONY: alp
alp: ## alpでアクセスログを確認する
	@./scripts/alp.sh

.PHONY: slow-query
slow-query: ## performance_schemaのクエリダイジェスト集計を表示する
	@./scripts/slow-query.sh

.PHONY: save-bench-log
save-bench-log: ## ベンチGUIの結果を標準入力から docs/bench/ に保存する（ローカルで実行）
	@./scripts/save-bench-log.sh

.PHONY: nd
nd: notify-discord-alp notify-discord-slow-query ## alp / slow-query の結果をDiscordに通知する

# notify-discord-alp / notify-discord-slow-query
notify-discord-%: FORCE ## alp / slow-query の結果をDiscordに通知する（notify-discord-alp など）
	./scripts/notify-discord.sh $*

# remote-notify-discord-alp-s1 / remote-notify-discord-slow-query-s1 など
remote-notify-discord-alp-%: FORCE ## ローカルから対象サーバーのalp結果をDiscordへ通知する（remote-notify-discord-alp-s1 など）
	REMOTE_DEPLOY_PATH=$(REMOTE_DEPLOY_PATH) ./scripts/remote.sh $* notify-discord alp

remote-notify-discord-slow-query-%: FORCE ## ローカルから対象サーバーのslow-query結果をDiscordへ通知する（remote-notify-discord-slow-query-s1 など）
	REMOTE_DEPLOY_PATH=$(REMOTE_DEPLOY_PATH) ./scripts/remote.sh $* notify-discord slow-query

.PHONY: remote-notify-discord-alp-all remote-notify-discord-slow-query-all
remote-notify-discord-alp-all: ## 全サーバーのalp結果をDiscordへ通知する（対象はSERVERSで調整）
	$(MAKE) -k -j $(words $(SERVERS)) $(addprefix remote-notify-discord-alp-,$(SERVERS))

remote-notify-discord-slow-query-all: ## 全サーバーのslow-query結果をDiscordへ通知する（対象はSERVERSで調整）
	$(MAKE) -k -j $(words $(SERVERS)) $(addprefix remote-notify-discord-slow-query-,$(SERVERS))

.PHONY: watch-service-log
watch-service-log: ## アプリケーションのログを確認する
	./scripts/watch-service-log.sh
