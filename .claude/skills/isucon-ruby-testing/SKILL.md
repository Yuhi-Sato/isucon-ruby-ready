---
name: isucon-ruby-testing
description: ISUCONのRuby実装（Rack互換アプリ。Sinatra等）で、リファクタ前にハンドラの振る舞いをDocker + minitest/rack-testで検証するときに使う。フレームワーク・出題ドメインに依存しない汎用手順。テスト環境の構築・再実行手順・test_helperの書き方・ハマりポイントをまとめる。「テストを書いて」「リファクタ前に動作確認したい」「このハンドラを検証して」などのリクエストで使用する。N+1解消・インデックス追加・リファクタ手順そのものは isucon-optimization-patterns スキルに委譲する。
---

# ISUCON Ruby ハンドラ検証テスト（Docker + minitest）

## 概要

リファクタ前に既存ハンドラの振る舞いを回帰テストで固定し、変更前後で壊れないことを確認する環境。本番DBに触れず、Docker 内で MySQL を立てて minitest + rack-test で検証する。フレームワーク・出題ドメイン非依存で、具体例は `webapp/<lang>` に合わせて読替える。

> **N+1解消・インデックス追加・リファクタ手順は本スキルでは扱わない。** isucon-optimization-patterns に委譲する。テストの書き方・実行方法のみに徹する。

## 適用条件

以下いずれかのリクエストで使う:

- 「リファクタ前にハンドラを Docker+minitest で検証する」
- 「テストを書いて」
- 「このエンドポイントをテストで固定したい」

## セットアップ: `webapp/<lang>/test` の構成

テスト一式はアプリのテスト用ディレクトリ（例: `webapp/ruby/test/`）以下に置く。構成は次の通り:

```
webapp/ruby/
└── test/
    ├── docker-compose.yml
    ├── Dockerfile          # テスト用Rubyイメージ（mysql2含む）
    ├── mysql/
    │   └── Dockerfile      # テスト用MySQLイメージ（DB作成・スキーマ投入）
    ├── test_helper.rb      # helper API + DB接続設定
    └── *_test.rb           # テスト本体
```

- **compose**: `tests` サービスが `test_helper.rb` を含むテストファイルを実行する
- **Dockerfile**: アプリの Gemfile を COPY して bundle install し、`mysql2` をネイティブビルドする
- **mysql/Dockerfile**: MySQL イメージに DB を作成し、アプリのスキーマを投入する
- **test_helper**: DB接続・初期化・フィクスチャ作成・認証ヘッダ・JSONパースなどの共通処理を提供する

## 起動・再実行

**このテスト環境はローカル開発機で実行する**（ISUCON当日のサーバーには Docker が無いことが多く、本番DBも汚さないため）。サーバー上での実行は想定しない。

`docker compose`（v2 サブコマンド。ハイフン版 `docker-compose` ではない）を使う。

初回（ビルド込み）:

```bash
docker compose up --build
```

コードを変更したら **imageを再ビルドしてから**再実行する（後述の bind mount 制約のため）:

```bash
docker compose build tests
docker compose run --rm tests
```

後片付け（起動サイクルの高速化・前回DB状態の汚染を防ぐため、再実行前に落とす）:

```bash
docker compose down
```

## ファイル一式の要点（各ファイルの役割と最小構成）

以下はテスト環境を再現するための各ファイルの構成例。出力するテスト対象のドメインに合わせて読替える。

### ビルドコンテキストと COPY パスの設計

`Dockerfile` はアプリの `Gemfile` を参照するため、**compose の `build.context` はアプリルート（`webapp/ruby`）に設定**し、`dockerfile` で `test/Dockerfile` を参照する。`build.context` を `test/` 配下にしてしまうと、アプリルートの `Gemfile` が COPY 範囲外になり失敗する。

```
webapp/ruby/
├── Gemfile
├── app.rb
└── test/
    ├── docker-compose.yml
    ├── Dockerfile
    ├── mysql/Dockerfile
    ├── test_helper.rb
    └── *_test.rb
```

### docker-compose.yml

**コンテキストを `..`（アプリルート）にして** `test/Dockerfile` を参照する:

```yaml
services:
  mysql:
    build: ./mysql
    environment:
      MYSQL_DATABASE: isucon
      MYSQL_USER: isucon
      MYSQL_PASSWORD: isucon
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "isucon", "-pisucon"]
      interval: 2s
      timeout: 2s
      retries: 20
      start_period: 5s
  tests:
    build:
      context: ..
      dockerfile: test/Dockerfile
    depends_on:
      mysql:
        condition: service_healthy
    environment:
      MYSQL_HOST: mysql
      MYSQL_PORT: "3306"
      MYSQL_DATABASE: isucon
      MYSQL_USER: isucon
      MYSQL_PASSWORD: isucon
    command: ["bundle", "exec", "rake", "test"]
```

- `MYSQL_*` は**アプリ本体の接続設定と一致**させる。`mysql` / `tests` 両サービスでズレると接続失敗
- healthcheck の `-u` / `-p` も `MYSQL_USER` / `MYSQL_PASSWORD` と一致させる。ズレると healthcheck が永遠に失敗（`MYSQL_ALLOW_EMPTY_PASSWORD` は使わない）

### Dockerfile（テスト用Rubyイメージ）

アプリの Gemfile を COPY して bundle install し、`mysql2` をネイティブビルドする。テストコードも COPY で取り込む（bind mount 非依存）。**`FROM ruby:*` はアプリの `.ruby-version` / Gemfile の `ruby` 宣言に一致させる**（ズレると bundle install 失敗）:

```dockerfile
FROM ruby:3.2     # ← アプリの .ruby-version / Gemfile の ruby宣言と一致させる
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
CMD ["bundle", "exec", "rake", "test"]
```

**ビルド時の COPY 範囲に注意**: `/app` に対象アプリ一式を取り込むが、必要最小限に留める。`.dockerignore` で除外するのは、`tmp/`・`log/`・`.git/`・`node_modules/`・不要なシード（`*-initial-data.sql.gz`）など。

### mysql/Dockerfile（テスト用MySQLイメージ）

MySQL イメージ上で DB 作成・スキーマ投入を行う。**アプリの実スキーマを投入する**（テストは本番と同じ DDL で検証する）:

```dockerfile
FROM mysql:8.0
COPY schema.sql /docker-entrypoint-initdb.d/01-schema.sql
```

- `schema.sql` はアプリの DB スキーマ（`CREATE TABLE` 群）。出題リポジトリの `sql/` 等から取得し `webapp/<lang>/test/mysql/` に配置
- `/docker-entrypoint-initdb.d/` は初回起動時に DB 作成後に自動実行され、`MYSQL_DATABASE` の DB に適用される。**init は `${MYSQL_USER}`（root でない）権限で実行される**ため `CREATE DATABASE` 等は入れず `CREATE TABLE` のみに留める
- 巨大な本番シード（`*-initial-data.sql.gz`）は**ここには入れない**（TRUNCATE + 最小シードで初期化するため）

### test_helper.rb の DB 接続設定

mysql2 で MySQL コンテナへ接続する。接続情報は compose で渡した環境変数から組み立てる（**接続先ホストは `mysql`（compose サービス名）**、ローカルの `localhost` ではない）:

```ruby
require "mysql2"
require "json"

DB = Mysql2::Client.new(
  host: ENV.fetch("MYSQL_HOST", "mysql"),
  port: ENV.fetch("MYSQL_PORT", "3306").to_i,
  database: ENV.fetch("MYSQL_DATABASE", "isucon"),
  username: ENV.fetch("MYSQL_USER", "isucon"),
  password: ENV.fetch("MYSQL_PASSWORD", "isucon")
)
```

### test_helper.rb の helper API

テスト内で共通して使うヘルパーは、アプリの構成に合わせて作る。最低限は以下（出題に応じて追加する）:

| helper | 役割 |
|---|---|
| `initialize_database!` | DBを TRUNCATE で初期化し、アプリ動作に必要な最小設定レコードをシードする |
| `next_id` | 一意な ID を返す |
| `create_user` | ユーザーを作成し、認証用トークンを返す（認証が複数種あるなら分けて作る） |

`initialize_database!` の実装例（`TRUNCATE` + 最小シード）:

```ruby
def initialize_database!
  DB.query("SET FOREIGN_KEY_CHECKS=0")
  %w[users settings rides].each { |t| DB.query("TRUNCATE #{t}") }
  DB.query("SET FOREIGN_KEY_CHECKS=1")
  DB.query("INSERT INTO settings (payment_gateway_url) VALUES ('http://localhost:9000')")
end
```

> シード対象テーブル・設定カラムは出題により変わるため、**上記の探索結果に基づいて**組み替える。

### DB に投入するデータを探索してセットアップする

シードすべきデータは**決め打ちせずアプリ実装から探索**して特定する:

1. **参照データの洗い出し**: スキーマ（`schema.sql` / DDL）、`POST /initialize` の投入内容、ハンドラが参照する設定値（例: 決済URL・料金表）を確認。**DB 接続設定**（ホスト・DB名・ユーザー・パスワード）も compose の `MYSQL_*` と一致させる
2. **最小セットの定義**: テストに必要な最小限だけ seed。本番シード（`*-initial-data.sql.gz`）は流さず TRUNCATE + 最小シード
3. **helper への反映**: テーブル名・カラムはハードコードせず探索で見つけた値を使用

### テストを独立させる（DB初期化の呼び出しタイミング）

`initialize_database!` は**各テストの実行前**（Minitest では `setup`）に呼び、テスト間で DB 状態を独立させる:

```ruby
class SampleTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    initialize_database!
  end
  # ...
end
```

- **各テストは他テストの状態に依存させない**。`create_user` / `next_id` はテスト単位で作り直す
- 順序依存・並列実行で壊れないよう `initialize_database!` は必ず `setup` で呼ぶ

### テスト実行コマンド

実行方法はアプリ構成に合わせて選ぶ。**Rakefile / rake が無いこともある**ため:
- `rake test`（Rakefile + minitest-rake がある場合）
- `ruby -Itest test/*_test.rb`（Rake を使わず直接実行する場合）

### rack-test の認証ヘッダ・JSON の書き方

認証は `Authorization` ヘッダにトークン、ボディは JSON で投げる（認証方式が APIキー/セッションなら合わせる）:

```ruby
require_relative "test_helper"

class SampleTest < Minitest::Test
  include Rack::Test::Methods

  def app
    App   # Sinatra: App / Roda: App(.app) / 素の rack: アプリオブジェクト
  end

  def test_create_resource
    token = create_user
    post "/api/resources",
         JSON.generate({ name: "sample", qty: 3 }),
         { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    refute_nil body["id"]
  end
end
```

## ハマりポイント

| ハマり | 対策 |
|---|---|
| bind mount が壊れる | 単一 `-v` バインドマウントは使えない。**COPY方式**でファイルを取り込み、**コード変更の度に再ビルド必須** |
| `Gemfile` が COPY 範囲外でビルド失敗 | `build.context` はアプリルート（`webapp/ruby`）に設定し、`dockerfile` で `test/Dockerfile` を参照する |
| Ruby バージョン不一致で bundle install 失敗 | `FROM ruby:*` をアプリの `.ruby-version` / Gemfile の `ruby` 宣言に一致させる |
| healthcheck の認証が `MYSQL_*` とズレて永遠に失敗 | `mysqladmin ping` の `-u` / `-p` を compose の `MYSQL_USER` / `MYSQL_PASSWORD` と一致させる。`MYSQL_ALLOW_EMPTY_PASSWORD` は使わない |
| ローカル開発機で mysql2 がネイティブビルド不可（server には入っている場合を除く） | Docker 内で `bundle install` しネイティブビルドする。ローカルで gem を入れ直す必要はない |
| `depends_on` だけで DB に接続できず失敗する | `condition: service_healthy` + ヘルスチェックで DB 接続可能を待ってからテストを実行する |
| テストから DB に接続できない（`localhost` のまま） | 接続ホストは compose サービス名 `mysql` を使う（`MYSQL_HOST` 環境変数で渡す） |
| `MYSQL_*`（DB名・ユーザー・パスワード）がアプリの接続設定とズレる | アプリが読む接続設定を探索し、compose と helper の `MYSQL_*` を一致させる |
| `3-initial-data.sql.gz` は使わない | 巨大シードを流さない。**TRUNCATE + 最小シード**で `initialize_database!` する |
| 必要な設定レコードのシード漏れ | アプリが起動時に参照する設定（例: 決済URL `payment_gateway_url` 等）を `initialize_database!` で必ず入れる。無いと該当APIが失敗する |
| 前回の MySQL データが残ってテストが汚染される | `docker compose down`（必要なら `-v` でボリュームごと削除）で後片付けする |
