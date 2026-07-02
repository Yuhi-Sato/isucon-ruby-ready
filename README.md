# isucon-ruby-ready

ISUCON本番当日に使う「サーバーセットアップ・ログ解析・デプロイ」用ツール一式。
[Yuhi-Sato/isucon-ready](https://github.com/Yuhi-Sato/isucon-ready)（Go版）のRuby版。

このリポジトリは **ツール群のみ** を提供し、ISUCON問題のアプリケーションコード（`webapp/ruby`以下）は含まない。
ISUCON運営配布リポジトリのルートに、このリポジトリの内容を展開して使う。

設計の背景・意図は [docs/superpowers/specs/2026-07-01-isucon-ruby-ready-design.md](docs/superpowers/specs/2026-07-01-isucon-ruby-ready-design.md) を参照。

## 当日チェックリスト

セットアップ後、最初に以下を問題に合わせて確認・修正する。

- [ ] `Makefile` の `SERVICE_NAME` を問題のサービス名に変更する（例: `isupipe-ruby.service`）
- [ ] `Makefile` の `APP_DIR` を確認する（`webapp/ruby` 以外の構成の場合）
- [ ] `Makefile` の `DB_SERVICE_NAME` を確認する（MariaDBの場合は `mariadb` 等に変更）
- [ ] `git-setup` 内の `git config` の `user.email` / `user.name` を確認する
- [ ] GitHub Secretsを登録する（[必要なSecrets](#必要なgithub-secrets)、[CI用SSH鍵のセットアップ](#ci用ssh鍵のセットアップ)を参照）
- [ ] `tool-config/alp/config.yml` の `matching_groups` を問題のURLパターンに合わせて編集する
- [ ] `tool-config/nginx/ltsv-log-format.conf` の内容をnginx.confに反映する
- [ ] `tool-config/alp/notify-slack.toml.example` / `tool-config/slow-query/notify-slack.toml.example` をコピーしてWebhook URLを設定する

## セットアップ

### s1（メインサーバー）

競技用サーバーにSSH接続し、ISUCON運営配布リポジトリのディレクトリ直下で以下を実行する。

```bash
curl -L https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=1

sh setup.sh
sh git.sh {自分たちのチームリポジトリのSSH URL}
```

`setup.sh` はツールのインストール・ディレクトリ準備・git設定・サーバー設定の取得までを行い、最後にSSH公開鍵を表示する。
表示された公開鍵をチームリポジトリのDeploy keyとして登録してから `git.sh` を実行すること。

`git.sh` は `git init` して自分たちのチームリポジトリをリモートに設定し、初回コミット・pushを行う。

### s2 / s3（2台目以降）

s1が作成・pushしたチームリポジトリを使う。tarball展開・`git.sh`は行わない。

```bash
git clone {自分たちのチームリポジトリのSSH URL} .
make setup
make set-as-s2   # s3の場合は set-as-s3
make get-conf
```

## Makefileターゲット一覧

| ターゲット | 用途 |
|---|---|
| `make setup` | ツールインストール・ディレクトリ準備・git設定（初回のみ） |
| `make get-conf` | サーバー上の実際のDB/nginx設定をリポジトリ管理下にコピーする |
| `make deploy-conf` | リポジトリ管理下のDB/nginx設定をサーバーに反映する |
| `make bench` | **ベンチマーク実行直前に手動で叩く。** `git pull` → `bundle install` → ログ削除 → 設定反映 → DB/nginx含む全再起動 |
| `make deploy` | **mainマージ時にCIから自動実行される軽量デプロイ。** `git pull` → `bundle install` → アプリのみ再起動（ログは消さない、DB/nginxは再起動しない） |
| `make remote-deploy-s1` | **ローカルから実行。** SSHで対象サーバーの`deploy.sh`を叩く（`-s2` / `-s3` も同様。[ローカルからのデプロイ](#ローカルからのデプロイ手動フォールバック兼用)参照） |
| `make remote-deploy-all` | **ローカルから実行。** 全サーバーへ並列デプロイし、失敗したサーバーがあれば最後にまとめて報告する |
| `make add-profiling-gems` | `bundle add vernier` を実行する。**ローカル専用**（[Vernierの導入](#vernierサンプリングプロファイラの導入)参照） |
| `make vernier-view` | `$(APP_DIR)/tmp/vernier` 以下の最新プロファイルをビューアで開く |
| `make alp` | nginxアクセスログ（ltsv）を`alp`で集計する |
| `make notify-slack-alp` | `alp`の結果をSlackに通知する |
| `make slow-query` | `pt-query-digest`でスロークエリログを集計する |
| `make notify-slack-slow-query` | スロークエリ集計結果をSlackに通知する |
| `make ns` | `notify-slack-alp` と `notify-slack-slow-query` をまとめて実行する |
| `make extract-queries` | アプリの`.rb`から実行しているSQLクエリ（クォート文字列・ヒアドキュメント）を`queries/`以下に抽出する |
| `make watch-service-log` | アプリのsystemdログを`journalctl -f`で確認する |
| `make rm-logs` | nginxアクセスログ・DBスロークエリログを削除する |

`bench` と `deploy` の使い分け: `deploy`はmainマージのたびにCIから自動で走るため、誰かが計測中に別メンバーがマージしただけでログが消えたりDBが瞬断したりしないよう、ログ削除・DB/nginx再起動を含めていない。ベンチマークを回す直前は必ず手動で `make bench` を叩くこと。

## Vernier（サンプリングプロファイラ）の導入

[Vernier](https://github.com/jhawthorn/vernier) はRuby 3.2.1以上が必要。問題のRubyバージョンが古い場合は導入できない。

### gemの追加

**ローカル（手元のリポジトリ）で実行し、`Gemfile` / `Gemfile.lock` の変更をコミット・pushする。**

```bash
make add-profiling-gems
git add Gemfile Gemfile.lock
git commit -m "Add vernier"
git push
```

サーバー上で直接実行しないこと。サーバーのワーキングツリーに変更が残ると、以後の `git pull`（`make bench` / `make deploy` の先頭ステップ）がconflictで失敗する。

### アプリへの組み込み

`config.ru` に以下のようなmiddlewareを追加する（Sinatra/Rackアプリを想定）。リクエストごとに記録すると重いため、環境変数などで有効/無効を切り替えられるようにしておくと当日の計測がしやすい。

```ruby
# config.ru
require "vernier"

use Rack::Static # など、既存のmiddlewareの後に追加

if ENV["ENABLE_VERNIER"] == "1"
  use Class.new do
    def initialize(app)
      @app = app
    end

    def call(env)
      FileUtils.mkdir_p("tmp/vernier")
      result = nil
      Vernier.trace(out: "tmp/vernier/#{Time.now.strftime('%Y%m%d-%H%M%S-%L')}.json") do
        result = @app.call(env)
      end
      result
    end
  end
end
```

### プロファイルの閲覧

```bash
make vernier-view
```

または出力されたJSONファイルを [profiler.firefox.com](https://profiler.firefox.com) にドラッグ&ドロップして閲覧する。

## N+1検出の運用

ISUCON公式のRuby参考実装は近年一貫してSinatra + mysql2（またはpg）を直接使う構成であり、ActiveRecordを前提とするN+1検出gem（Prosopiteなど）は検出対象のイベントが流れず機能しない。そのため本リポジトリではN+1検出をgemに頼らず、スロークエリログの集計で代用する。

```bash
make slow-query
```

`pt-query-digest`の出力の `Count` 列（同一クエリパターンの実行回数）を見て、リクエスト数に対して極端に多いクエリがあればN+1を疑う。

## 必要なGitHub Secrets

CIからの自動デプロイ（`.github/workflows/deploy.yml`）に必要。

| Secret名 | 用途 |
|---|---|
| `SSH_PRIVATE_KEY` | CI専用のSSH秘密鍵（全サーバー共通） |
| `SSH_USER` | SSHユーザー名（通常 `isucon`） |
| `SSH_HOST_S1` / `SSH_HOST_S2` / `SSH_HOST_S3` | 各サーバーのホスト名/IP |
| `DEPLOY_PATH` | サーバー上のリポジトリ配置パス |

使わないサーバーがある場合は、`.github/workflows/deploy.yml`から該当する`deploy-sN`ジョブを削除すること。削除しないとpushのたびに失敗ジョブの赤いXが出続ける。

### CI用SSH鍵のセットアップ

1. 手元でCI専用の鍵ペアを作成する（`git-setup`がサーバー上で作るdeploy keyとは別物）
   ```bash
   ssh-keygen -t ed25519 -f ci_deploy_key -N ""
   ```
2. 公開鍵（`ci_deploy_key.pub`）を **各サーバー** の `~/.ssh/authorized_keys` に追記する
3. 秘密鍵（`ci_deploy_key`）の内容をGitHub Secretsの `SSH_PRIVATE_KEY` に登録する

### ローカルからのデプロイ（手動フォールバック兼用）

mainマージを待たずに手元からデプロイしたいときや、GitHub ActionsのランナーからサーバーへSSH到達できないときは、ローカルから直接デプロイできる。

```bash
make remote-deploy-s1    # 対象サーバーのみ（remote-deploy-s2 / -s3 も同様）
make remote-deploy-all   # 全サーバーへ並列デプロイ
```

前提として、ローカルの `~/.ssh/config` に各サーバーのHostを `s1` / `s2` / `s3` の名前で定義しておくこと:

```
Host s1
  HostName <s1のIPアドレス>
  User isucon

Host s2
  HostName <s2のIPアドレス>
  User isucon

Host s3
  HostName <s3のIPアドレス>
  User isucon
```

- サーバー上の配置パスがホームディレクトリ以外の場合は `make remote-deploy-s1 REMOTE_DEPLOY_PATH=<パス>` で上書きする
- 使わないサーバーがある場合は `make remote-deploy-all SERVERS="s1 s2"` のように対象を絞れる
- `remote-deploy-all` は並列実行（`make -k -j`）のため出力が交錯することがある。失敗したサーバーがあっても残りへ続行し、最後にまとめて報告して非0で終了する

### deploy.shの既知の制約

`deploy.sh` 自身への変更は、その回の `git pull`（`make deploy`内）より前に実行されるため1回のデプロイでは反映されない。反映されるのは次のデプロイから。
