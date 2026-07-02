ifneq ("$(wildcard /home/isucon/env.sh)","")
    include /home/isucon/env.sh
endif

# SERVER_ID: env.sh内で定義

# 問題によって変わる変数 ------------------------
USER:=isucon
APP_DIR:=./webapp/ruby
SERVICE_NAME:=isu-ruby
DB_SERVICE_NAME:=mysql

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx

DB_SLOW_LOG:=/var/log/mysql/mysql-slow.log
NGINX_LOG:=/var/log/nginx/access.log

NOTIFY_SLACK_TMPFILE:=tmp/notify-slack.txt

# alp / notify_slack のバイナリ選択に使う（arm環境での素振りにも対応）
ARCH:=$(shell dpkg --print-architecture 2>/dev/null || echo amd64)

# 引数なしのmakeで setup が走らないように、デフォルトはヘルプ表示にする
.DEFAULT_GOAL := help

.PHONY: help
help: ## ターゲット一覧を表示する
	@grep -hE '^[a-zA-Z0-9_%-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

# メインで使うコマンド ------------------------

.PHONY: setup
setup: install-tools dir-setup git-setup ## サーバーの環境構築（ツールのインストール、gitまわりのセットアップ）

.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-envsh ## 設定ファイルなどを取得してgit管理下に配置する

.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-envsh ## リポジトリ内の設定ファイルをそれぞれ配置する

.PHONY: bench
bench: ## ベンチマーク直前に実行する（ログ削除・設定反映・DB/nginx含む全再起動）
	git pull
	$(MAKE) check-server-id
	$(MAKE) bundle-install
	$(MAKE) rm-logs
	$(MAKE) deploy-conf
	$(MAKE) restart

.PHONY: deploy
deploy: ## mainマージ時の自動デプロイで使う（ログは消さない・DB/nginxは再起動しない）
	git pull
	$(MAKE) check-server-id
	$(MAKE) bundle-install
	$(MAKE) restart-app

.PHONY: ns
ns: notify-slack-alp notify-slack-slow-query ## notify_slack系をまとめて通知する

.PHONY: slow-query
slow-query: ## slow queryを確認する
	sudo pt-query-digest $(DB_SLOW_LOG)

.PHONY: alp
alp: ## alpでアクセスログを確認する
	sudo alp ltsv --file=$(NGINX_LOG) --config=tool-config/alp/config.yml

# notify-slack-alp / notify-slack-slow-query
# `$*`（alp / slow-query）がmakeターゲット名とtool-config/のディレクトリ名を兼ねる
notify-slack-%: ## alp / slow-query の結果をSlackに通知する（notify-slack-alp など）
	$(MAKE) refresh-notify-slack-tmp
	mkdir -p tmp && $(MAKE) $* >> $(NOTIFY_SLACK_TMPFILE)
	cat $(NOTIFY_SLACK_TMPFILE) | notify_slack -c tool-config/$*/notify-slack.toml -snippet -filename=$$(date "+%Y-%m-%d-%H:%M:%S").txt

.PHONY: add-profiling-gems
add-profiling-gems: ## Vernier用gemを追加する（ローカル専用。詳細はREADME参照）
	./scripts/add-profiling-gems.sh $(APP_DIR)

.PHONY: vernier-view
vernier-view: ## 直近のVernierプロファイルをビューアで開く（tmp/vernier以下に出力する想定）
	$(eval latest := $(shell ls -t $(APP_DIR)/tmp/vernier/*.json 2>/dev/null | head -n 1))
	@test -n "$(latest)" || { echo "no profile found in $(APP_DIR)/tmp/vernier"; exit 1; }
	cd $(APP_DIR) && bundle exec vernier view $(abspath $(latest))

.PHONY: extract-sql extract-queries
extract-sql: extract-select extract-insert extract-update extract-delete ## SQLクエリを*.rbから抽出してqueries/以下に出力する
extract-queries: extract-select extract-insert extract-update extract-delete

.PHONY: watch-service-log
watch-service-log: ## アプリケーションのログを確認する
	sudo journalctl -u $(SERVICE_NAME) -n10 -f

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	sudo apt update

	sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree \
		build-essential libmysqlclient-dev libpq-dev zlib1g-dev libyaml-dev

	# alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.21/alp_linux_$(ARCH).zip
	unzip alp_linux_$(ARCH).zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_$(ARCH).zip alp

	# notify_slackのインストール
	wget https://github.com/catatsuy/notify_slack/releases/download/v0.5.12/notify_slack-linux-$(ARCH).tar.gz
	tar -xvf notify_slack-linux-$(ARCH).tar.gz
	sudo install notify_slack /usr/local/bin/notify_slack
	rm notify_slack-linux-$(ARCH).tar.gz notify_slack LICENSE CHANGELOG.md README.md

.PHONY: dir-setup
dir-setup:
	mkdir -p tool-config/alp tool-config/slow-query tool-config/nginx queries
	touch queries/.keep

.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "yuhi120101@gmail.com"
	git config --global user.name "Yuhi-Sato"

	# deploykeyの作成（既にあればスキップ。パスフレーズなしで非対話生成）
	test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

# set-as-s1 / set-as-s2 / set-as-s3
set-as-%: ## このサーバーをs1/s2/s3として設定する（set-as-s1 など）
	mkdir -p $*$(DB_PATH) $*$(NGINX_PATH)
	cp -R /home/isucon/env.sh $*/env.sh
	echo "" >> $*/env.sh
	echo "" >> ~/env.sh
	echo "SERVER_ID=$*" >> $*/env.sh
	echo "SERVER_ID=$*" >> ~/env.sh

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* $(SERVER_ID)$(DB_PATH)
	sudo chown -R $(USER) $(SERVER_ID)$(DB_PATH)

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* $(SERVER_ID)$(NGINX_PATH)
	sudo chown -R $(USER) $(SERVER_ID)$(NGINX_PATH)

.PHONY: get-envsh
get-envsh:
	cp ~/env.sh $(SERVER_ID)/env.sh

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R $(SERVER_ID)$(DB_PATH)/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R $(SERVER_ID)$(NGINX_PATH)/* $(NGINX_PATH)

.PHONY: deploy-envsh
deploy-envsh:
	cp $(SERVER_ID)/env.sh ~/env.sh

.PHONY: bundle-install
bundle-install:
	cd $(APP_DIR) && bundle install

.PHONY: restart
restart: ## アプリ・DB・nginxをすべて再起動する
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart $(DB_SERVICE_NAME)
	sudo systemctl restart nginx

.PHONY: restart-app
restart-app: ## アプリのみ再起動する（自動デプロイ用。DB/nginxは触らない）
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)

# rm ではなく truncate を使う: rm だと書き込み中のプロセスが削除済みinodeに
# 書き続けて新しいログが取れない。truncate ならプロセス再起動なしでログを空にできる
.PHONY: rm-logs
rm-logs: ## アクセスログ・スロークエリログを空にする
	test ! -f $(NGINX_LOG) || sudo truncate -s 0 $(NGINX_LOG)
	test ! -f $(DB_SLOW_LOG) || sudo truncate -s 0 $(DB_SLOW_LOG)

.PHONY: refresh-notify-slack-tmp
refresh-notify-slack-tmp:
	rm -f $(NOTIFY_SLACK_TMPFILE)
	mkdir -p tmp
	touch $(NOTIFY_SLACK_TMPFILE)

# extract-select / extract-insert / extract-update / extract-delete
# 一行のクォート文字列クエリと、ヒアドキュメント（<<~SQL 等）で書かれたクエリの両方を抽出する
extract-%:
	$(eval kw := $(shell echo $* | tr a-z A-Z))
	mkdir -p queries
	find $(APP_DIR) -name "*.rb" | xargs -r grep -h -oE "\"$(kw)[^\"]*\"|'$(kw)[^']*'" | sed -E "s/^[\"']//; s/[\"']$$//" > queries/$*.sql
	echo >> queries/$*.sql
	echo ----------------------------------------- heredoc queries ----------------------------------------- >> queries/$*.sql
	find $(APP_DIR) -name "*.rb" | xargs -r awk -v kw=$(kw) '/<<[-~]?SQL/ { capture=1; buf=""; next } capture && /^[[:space:]]*SQL[[:space:]]*$$/ { capture=0; if (buf ~ kw) printf "%s", buf; next } capture { buf = buf $$0 "\n" }' >> queries/$*.sql
