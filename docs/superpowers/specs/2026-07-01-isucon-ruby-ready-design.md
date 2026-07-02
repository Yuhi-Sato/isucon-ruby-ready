# isucon-ruby-ready 設計書

## 背景・目的

ISUCON本番当日に使う「サーバーセットアップ・ログ解析・デプロイ」用のツール一式を集約したリポジトリを作成する。
[Yuhi-Sato/isucon-ready](https://github.com/Yuhi-Sato/isucon-ready)（Go版）を参考にしつつ、Ruby参考実装で使うことを想定して以下を追加する。

- サンプリングプロファイラ: [Vernier](https://github.com/jhawthorn/vernier)
- N+1検出: [Prosopite](https://github.com/charkost/prosopite)
- デプロイスクリプトと、mainマージ時に自動デプロイするGitHub Actionsワークフロー

## スコープ

- **本リポジトリにはISUCON問題のアプリケーションコード（`webapp/ruby`以下）を含めない。** 参考リポジトリと同様、サーバーセットアップ／ログ解析／デプロイ用のツール群のみを提供する「テンプレートリポジトリ」とする。
- 実際の競技では、このリポジトリの内容をISUCON運営配布リポジトリのルートに配置して使う（reference の `README.md` にある `wget` 手順を踏襲）。
- Vernier/Prosopiteは「アプリへの組み込みコード（middleware等）」までは提供しない。`bundle add` によるgem追加を自動化するスクリプトのみ提供し、実際の組み込みは各チームのアプリ側の責務とする。

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
│   ├── alp/.keep
│   └── slow-query/.keep
├── .github/
│   └── workflows/
│       └── deploy.yml
└── .gitignore
```

## Makefile

reference の Makefile をベースに、Go固有の処理をRuby向けに置き換える。

| 変更 | 内容 |
|---|---|
| `BUILD_DIR` → `APP_DIR` | デフォルト `webapp/ruby`。ISUCON公式問題のディレクトリ構成（`webapp/<lang>`）に合わせる |
| `SERVICE_NAME` | デフォルト `isu-ruby`。問題ごとに変わるため、READMEで変更を促す |
| `build` → `bundle-install` | `cd $(APP_DIR); bundle install` に置換。Goのビルドステップを撤去 |
| `install-tools` | 既存のツール群（percona-toolkit, dstat, git, unzip, snapd, graphviz, tree, alp, notify_slack）に加え、Rubyのネイティブ拡張gemに必要な `build-essential libmysqlclient-dev libpq-dev zlib1g-dev libyaml-dev` を追加 |
| `add-profiling-gems`（新設） | `scripts/add-profiling-gems.sh $(APP_DIR)` を呼び出す |
| `extract-select/insert/update/delete` | 対象を `*.go` → `*.rb` に変更した grep/sed に置換。Goのバッククォート生文字列判定ロジックは撤去（Rubyには存在しないため）し、シングル/ダブルクォート文字列からの抽出のみ行う |
| `pprof-record` / `pprof-check` | 削除（`go tool pprof` はGo専用）。Vernierプロファイルの閲覧方法はREADMEに記載する（`bundle exec vernier view <file>`） |
| `bench`, `dir-setup`, `git-setup`, `check-server-id`, `set-as-s1/s2/s3`, `get-conf`, `deploy-conf`, `restart`, `rm-logs`, `alp`, `notify-slack-alp`, `notify-slack-slow-query`, `slow-query` | reference と同じロジックを踏襲する |

`bench` ターゲットの内容（変更なし、依存先のみRuby向けに読み替え）:
```makefile
bench:
	git pull
	make check-server-id
	make bundle-install
	make rm-logs
	make deploy-conf
	make restart
```

## scripts/add-profiling-gems.sh

```bash
#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
bundle add vernier prosopite
```

`make add-profiling-gems` から呼び出せるようにする。Vernier/Prosopiteの実際の計測コード（middleware組み込み等）はアプリ側の責務であり、本リポジトリのスコープ外。

## deploy.sh（新規）

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"
make bench
```

CI（GitHub Actions）・手動デプロイの両方から同じエントリポイントを使う。`make bench` が `git pull` を含むため、リモートで実行するだけで最新化される。

## .github/workflows/deploy.yml

- トリガー: `push` イベント、対象ブランチ `main`（マージも含む）
- ジョブ: `deploy-s1` / `deploy-s2` / `deploy-s3` の3つを明示的に定義する（matrixでの動的secret参照は行わない。GitHub Actionsの `secrets` コンテキストを式で動的にインデックスする挙動が環境依存で不安定なため、可読性・確実性を優先し3ジョブを個別記述する）
- 各ジョブは並列実行、失敗しても他ジョブをブロックしない
- 各ジョブは `appleboy/ssh-action` を使い、対象サーバーにSSH接続して `cd $DEPLOY_PATH && ./deploy.sh` を実行する
- 使わないサーバー用のジョブはチームごとにワークフローファイルから削除してもらう想定（READMEに明記）

必要な GitHub Secrets:

| Secret名 | 用途 |
|---|---|
| `SSH_PRIVATE_KEY` | 全サーバー共通のSSH秘密鍵 |
| `SSH_USER` | SSHユーザー名（デフォルト想定: `isucon`） |
| `SSH_HOST_S1` / `SSH_HOST_S2` / `SSH_HOST_S3` | 各サーバーのホスト名/IP |
| `DEPLOY_PATH` | サーバー上のリポジトリ配置パス |

## .gitignore

Ruby向けに以下を無視する:
```
vendor/bundle
.bundle/
log/
tmp/
*.gem
/tool-config/alp/notify-slack.toml
/tool-config/slow-query/notify-slack.toml
```

## README.md

- reference と同様の `wget` によるセットアップ手順（`Makefile`, `setup.sh`, `git.sh`, `deploy.sh`, `scripts/add-profiling-gems.sh` を取得）
- 必要な GitHub Secrets 一覧（上表）
- Vernier/Prosopite 導入手順（`make add-profiling-gems`）とVernierプロファイルの閲覧方法（`bundle exec vernier view <file>` または https://profiler.firefox.com にJSONをドラッグ）
- Makefileターゲット一覧表

## 検証方針

競技サーバー環境そのものは用意できないため、以下の範囲で検証する。

- `shellcheck` で `setup.sh` / `git.sh` / `deploy.sh` / `scripts/add-profiling-gems.sh` を静的解析
- `make -n <target>` で各Makefileターゲットのドライラン確認（実行はしない）
- GitHub Actionsワークフローは `actionlint` があれば静的解析、なければYAML構文チェックのみ
