# isucon-ruby-ready 設計書

> **Note:** 本設計書のうち、セットアップフロー（`setup.sh`/`server-setup.sh`/s2・s3手順）とCIのSecrets/Variables方式は、[2026-07-04-setup-flow-unification.md](2026-07-04-setup-flow-unification.md)で更新されている。以下の本文（特に「## Makefile」「## deploy.sh」「## .github/workflows/deploy.yml」節のセットアップ関連記述）は当時の設計判断の記録として残すが、現行の実装・READMEは新設計書に従う。

## 背景・目的

ISUCON本番当日に使う「サーバーセットアップ・ログ解析・デプロイ」用のツール一式を集約したリポジトリを作成する。
[Yuhi-Sato/isucon-ready](https://github.com/Yuhi-Sato/isucon-ready)（Go版）を参考にしつつ、Ruby参考実装で使うことを想定して以下を追加する。

- サンプリングプロファイラ: [Vernier](https://github.com/jhawthorn/vernier)
- デプロイスクリプトと、mainマージ時に自動デプロイするGitHub Actionsワークフロー

### Prosopite を採用しない理由（決定記録）

当初 N+1 検出に [Prosopite](https://github.com/charkost/prosopite) の採用を検討したが、**採用しない**。
Prosopite は `ActiveSupport::Notifications` の `sql.active_record` イベントを購読して N+1 を検出する仕組みであり、ActiveRecord が前提。ISUCON の公式 Ruby 参考実装は近年一貫して Sinatra + mysql2（または pg）直叩きで ActiveRecord を使わないため、gem を追加しても検出対象のイベントが流れず機能しない。

代替として、N+1 は **スロークエリログ + `pt-query-digest` の Count 列**（同一クエリパターンの実行回数）で検出する運用とし、READMEにその手順を明記する。

## スコープ

- **本リポジトリにはISUCON問題のアプリケーションコード（`webapp/ruby`以下）を含めない。** 参考リポジトリと同様、サーバーセットアップ／ログ解析／デプロイ用のツール群のみを提供する「テンプレートリポジトリ」とする。
- 実際の競技では、このリポジトリの内容をISUCON運営配布リポジトリのルートに配置して使う（後述のtarball展開手順）。
- Vernierの「アプリへの組み込みコード」は、**コードとしては提供しないが、READMEにコピペ可能なスニペットを掲載する**。公式Ruby実装はほぼSinatra（Rack）なので、`config.ru` に貼るだけの `Vernier::Middleware` スニペットを用意する。gem追加だけでは何も計測されないため、ドキュメントとしての提供までは本リポジトリの責務とする。

## リポジトリ構成

```
isucon-ruby-ready/
├── README.md
├── Makefile
├── setup.sh
├── git.sh
├── deploy.sh
├── scripts/
│   └── add-profiling-gems.sh
├── tool-config/
│   ├── alp/
│   │   ├── config.yml              # matching groups のサンプル入りテンプレ
│   │   └── notify-slack.toml.example
│   ├── slow-query/
│   │   └── notify-slack.toml.example
│   └── nginx/
│       └── ltsv-log-format.conf    # nginx.conf に貼る log_format ltsv スニペット
├── .github/
│   └── workflows/
│       └── deploy.yml
└── .gitignore
```

reference では `tool-config/alp/` に `.keep` しか置いていないが、`make alp` は `--config=tool-config/alp/config.yml` を参照するため、**config.yml が無いと alp 系ターゲットは動かない**。さらに `alp ltsv` は nginx 側が ltsv フォーマットで出力していることが前提のため、nginx.conf に貼る `log_format ltsv ...` スニペットも同梱する。`notify-slack.toml` は Webhook URL を含むため gitignore 対象とし、`.example` を同梱して当日コピーして使う。

## Makefile

reference の Makefile をベースに、Go固有の処理をRuby向けに置き換える。

| 変更 | 内容 |
|---|---|
| `BUILD_DIR` → `APP_DIR` | デフォルト `webapp/ruby`。ISUCON公式問題のディレクトリ構成（`webapp/<lang>`）に合わせる |
| `SERVICE_NAME` | デフォルト `isu-ruby`。問題ごとに変わる（公式は `isupipe-ruby.service` 等）ため、READMEの当日チェックリストで変更を促す |
| `DB_SERVICE_NAME`（新設） | デフォルト `mysql`。MariaDB の年もあるため、restart 対象のDBサービス名を変数化する |
| `build` → `bundle-install` | `cd $(APP_DIR); bundle install` に置換。Goのビルドステップを撤去 |
| `install-tools` | 既存のツール群（percona-toolkit, dstat, git, unzip, snapd, graphviz, tree, alp, notify_slack）に加え、Rubyのネイティブ拡張gemに必要な `build-essential libmysqlclient-dev libpq-dev zlib1g-dev libyaml-dev` を追加 |
| `add-profiling-gems`（新設） | `scripts/add-profiling-gems.sh $(APP_DIR)` を呼び出す。**ローカル実行専用**（後述） |
| `deploy`（新設） | 自動デプロイ用の軽量ターゲット。`git pull` → `check-server-id` → `bundle-install` → `restart-app`。**rm-logs / deploy-conf を含まない**（後述） |
| `restart-app`（新設） | `daemon-reload` + アプリのsystemdサービス（`$(SERVICE_NAME)`）のみ再起動。DB・nginxは再起動しない |
| `extract-select/insert/update/delete` | 対象を `*.go` → `*.rb` に変更。Goのバッククォート生文字列判定ロジックは撤去し、代わりに **Rubyのヒアドキュメント（`<<~SQL` 〜 終端 `SQL` 行）を抽出する awk** を追加する。Ruby参考実装はSQLをヒアドキュメントで書くことが多く、クォート文字列のみの抽出では主要クエリを取りこぼすため |
| `pprof-record` / `pprof-check` | 削除（`go tool pprof` はGo専用）。Vernierプロファイルの閲覧方法はREADMEに記載する（`bundle exec vernier view <file>`） |
| `bench`, `dir-setup`, `git-setup`, `check-server-id`, `set-as-s1/s2/s3`, `get-conf`, `deploy-conf`, `restart`, `rm-logs`, `alp`, `notify-slack-alp`, `notify-slack-slow-query`, `slow-query` | reference と同じロジックを踏襲する（`restart` のDBサービス名のみ `$(DB_SERVICE_NAME)` に変数化） |

### deploy と bench の分離（設計判断）

「デプロイ（アプリ更新）」と「ベンチ前準備（ログ消去・設定反映・全再起動）」は目的が別物であり、混ぜると事故になるため分離する。

- `make bench`: ベンチ実行直前に人間が叩く。`rm-logs`（アクセスログ・スロークエリログの削除）、`deploy-conf`（DB/nginx設定の反映）、`restart`（DB・nginx含む全再起動）を含む。reference と同じ。
- `make deploy`: GitHub Actions からの自動デプロイで使う。mainマージのたびに走るため、**ログを消さない・DBとnginxを再起動しない**。これを怠ると、誰かが計測中に別メンバーがマージしただけで解析前のログが消え、DBが瞬断する。

```makefile
bench:
	git pull
	make check-server-id
	make bundle-install
	make rm-logs
	make deploy-conf
	make restart

deploy:
	git pull
	make check-server-id
	make bundle-install
	make restart-app

restart-app:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
```

## scripts/add-profiling-gems.sh

```bash
#!/bin/bash
set -euo pipefail
APP_DIR="${1:-.}"
cd "$APP_DIR"
bundle add vernier
```

**実行場所はローカル（手元のリポジトリ）とし、実行後に Gemfile / Gemfile.lock をコミットしてpushするフローとする。** サーバー上で実行すると Gemfile / Gemfile.lock がワーキングツリー上で変更され、以後の `git pull`（`bench` / `deploy` の先頭ステップ）が conflict で失敗するため、サーバーでは実行しない。この注意はスクリプト内コメントとREADMEの両方に明記する。

制約: Vernier は **Ruby 3.2.1以上** が必要。問題のRubyが古い場合は導入できないことをREADMEに明記する。

Vernierの計測コード（Rack middleware組み込み等）はアプリ側の責務だが、READMEに `config.ru` へのコピペスニペットを掲載する（スコープ節参照）。

## deploy.sh（新規）

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# GitHub Actions からの SSH は非ログイン・非対話シェルのため、
# rbenv / xbuild でインストールされた Ruby の PATH が通らない。明示的に読み込む。
[ -f "$HOME/env.sh" ] && . "$HOME/env.sh"
export PATH="$HOME/local/ruby/bin:$HOME/.rbenv/shims:$PATH"

make deploy
```

- CI（GitHub Actions）・手動デプロイの両方から同じエントリポイントを使う。
- `make bench` ではなく軽量な `make deploy` を呼ぶ（前述の分離判断）。
- **既知の制約**: deploy.sh 自身への変更は `git pull` より前に実行されるため、1回遅れで反映される。READMEに明記する。

## .github/workflows/deploy.yml

- トリガー: `push` イベント、対象ブランチ `main`（マージも含む）
- ジョブ: `deploy-s1` / `deploy-s2` / `deploy-s3` の3つを明示的に定義する（matrixでの動的secret参照は行わない。GitHub Actionsの `secrets` コンテキストを式で動的にインデックスする挙動が環境依存で不安定なため、可読性・確実性を優先し3ジョブを個別記述する）
- **各ジョブに `concurrency` を設定する**: `group: deploy-s1`（サーバーごと）、`cancel-in-progress: true`。連続マージで同一サーバーへのデプロイが並行実行されると `git pull` や restart が競合するため、サーバー単位で直列化する
- 各ジョブは並列実行、失敗しても他ジョブをブロックしない
- 各ジョブは `appleboy/ssh-action` を使い、対象サーバーにSSH接続して `cd $DEPLOY_PATH && ./deploy.sh` を実行する
- 使わないサーバー用のジョブはチームごとにワークフローファイルから削除してもらう想定（READMEに明記）。削除し忘れると毎push失敗ジョブの赤いXが出続けるトレードオフがあるが、当日の構成把握のしやすさ（ファイルを見れば対象サーバーがわかる）を優先し、変数によるon/off切り替えは採用しない

必要な GitHub Secrets:

| Secret名 | 用途 |
|---|---|
| `SSH_PRIVATE_KEY` | CI専用のSSH秘密鍵（全サーバー共通） |
| `SSH_USER` | SSHユーザー名（デフォルト想定: `isucon`） |
| `SSH_HOST_S1` / `SSH_HOST_S2` / `SSH_HOST_S3` | 各サーバーのホスト名/IP |
| `DEPLOY_PATH` | サーバー上のリポジトリ配置パス |

### CI用SSH鍵のセットアップ手順（READMEに記載）

1. 手元で CI 専用の鍵ペアを作成する（`ssh-keygen -t ed25519 -f ci_deploy_key`。サーバー上で `git-setup` が作る deploy key とは別物）
2. 公開鍵を **各サーバー**の `~/.ssh/authorized_keys` に追記する
3. 秘密鍵を GitHub Secrets の `SSH_PRIVATE_KEY` に登録する

### ローカルからのデプロイ（手動フォールバック兼用）

競技環境によっては GitHub Actions のランナーからサーバーへSSH到達できない可能性があるほか、mainマージを待たずに手元から直接デプロイしたいケースもある。そのため、ローカルマシンから実行するMakefileターゲットを用意する:

```bash
make remote-deploy-s1    # 対象サーバーのみ（remote-deploy-s2 / -s3 も同様）
make remote-deploy-all   # 全サーバーへ並列デプロイ。失敗したサーバーがあれば最後にまとめて報告
```

- `~/.ssh/config` に `Host s1` / `s2` / `s3`（User isucon、各サーバーのIP）を定義しておくことが前提。設定例をREADMEに記載する
- サーバー上の配置パスは `REMOTE_DEPLOY_PATH`（デフォルト `/home/isucon`）、対象サーバーは `SERVERS`（デフォルト `s1 s2 s3`）で調整する
- `remote-deploy-all` は `make -k -j` による並列実行。失敗したサーバーがあっても残りへ続行し、最後にまとめて報告して非0で終了する（1台の不調が全体のデプロイを止めないようにするため）

## .gitignore

Ruby向けに以下を無視する:
```
vendor/bundle
/.bundle/
log/
tmp/
*.gem
/tool-config/alp/notify-slack.toml
/tool-config/slow-query/notify-slack.toml
```

注意: `.bundle/` をパス指定なしで書くと全階層にマッチし、公式問題が `webapp/ruby/.bundle/config`（bundle path 設定）を同梱している場合にそれまで無視してしまう。bundle path 設定は各サーバーで共有したいため、**ルート直下のみを対象とする `/.bundle/` にする**。`vendor/bundle` `log/` `tmp/` は `webapp/ruby` 以下で発生するものを無視する意図で、あえてパス指定なしのままとする。

## README.md

- **当日チェックリスト（README冒頭に置く）**:
  1. Makefile の `SERVICE_NAME` を問題のサービス名に変更（例: `isupipe-ruby.service`）
  2. `APP_DIR` の確認（`webapp/ruby` 以外の構成の場合）
  3. `DB_SERVICE_NAME` の確認（MariaDB の場合は変更）
  4. `git-setup` 内の git user.email / user.name の確認
  5. GitHub Secrets の登録（CI用SSH鍵の手順を含む）
  6. `tool-config/alp/config.yml` の matching groups を問題のURLパターンに合わせて編集
  7. nginx.conf に ltsv の `log_format` を反映（`tool-config/nginx/ltsv-log-format.conf` 参照）
  8. `notify-slack.toml.example` をコピーして Webhook URL を設定
- セットアップ手順は reference の `wget` 個別列挙方式ではなく、tarball展開方式を採用する:
  ```bash
  curl -L https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
    | tar xz --strip-components=1
  ```
  理由: 本リポジトリは reference（フラットな3ファイルのみ）と異なり `scripts/`, `tool-config/`, `.github/workflows/` などディレクトリを含むため、`wget`によるファイル単位の列挙はディレクトリを取得できずファイル追加のたびにREADMEの更新が必要になる。tarball展開なら1コマンドで全ファイル・ディレクトリを取得でき、`.git`も生成されないため後続の`git.sh`（独自リポジトリへの`git init`）と衝突しない。
- **サーバー別セットアップフロー**を明記する:
  - **s1**: tarball展開 → `setup.sh` → `git.sh <チームリポジトリURL>`（git init + 初回push）
  - **s2 / s3**: s1 が push したチームリポジトリを `git clone` する（tarball展開・git.sh は行わない）→ `make setup` → `make set-as-s2`（または s3）→ `make get-conf`
- 必要な GitHub Secrets 一覧・CI用SSH鍵のセットアップ手順・手動フォールバック（上記）
- Vernier 導入手順: ローカルで `make add-profiling-gems` → コミット・push（サーバーで実行してはいけない理由も記載）。`config.ru` に貼る `Vernier::Middleware` のコピペスニペット。プロファイルの閲覧方法（`bundle exec vernier view <file>` または https://profiler.firefox.com にJSONをドラッグ）。Ruby 3.2.1+ 制約
- **N+1検出の運用**: `make slow-query`（pt-query-digest）の Count 列で同一クエリパターンの実行回数を見る手順を記載（Prosopite不採用の経緯は本設計書参照）
- deploy.sh 自身の変更は1デプロイ遅れで反映される制約
- Makefileターゲット一覧表（`deploy` と `bench` の使い分けを含む）

## 検証方針

競技サーバー環境そのものは用意できないため、以下の範囲で検証する。

- `shellcheck` で `setup.sh` / `git.sh` / `deploy.sh` / `scripts/add-profiling-gems.sh` を静的解析
- `make -n <target>` で各Makefileターゲットのドライラン確認
- GitHub Actionsワークフローは `actionlint` で静的解析する（「あれば」ではなく検証の必須ツールとして導入する）
- **Ubuntu 22.04 / 24.04 の Docker コンテナで `make install-tools` と extract 系ターゲットを実際に実行して検証する**（静的解析だけでは apt パッケージ名の誤りや awk の抽出ロジックを検証できないため）。systemd 依存のターゲット（restart 等）はドライランのみ
- `install-tools` の alp / notify_slack はバージョンを固定せず `releases/latest/download/` URL（常に最新リリースへリダイレクト）でダウンロードする。バージョン番号のメンテナンスが不要になる代わりに、実行時点の最新リリースに依存するため、素振り時に一度 `make install-tools` を通して動作確認しておくこと
