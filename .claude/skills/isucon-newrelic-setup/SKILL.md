---
name: isucon-newrelic-setup
description: ISUCONのRuby（Sinatra/Rack）アプリにNew Relic Ruby Agentを導入し、キーを安全に環境変数で渡して計測できる状態にする。APM計測を一時的に有効化したいときに使い、最終ベンチの性能を測るだけの依頼には使わない。
---

# ISUCON New Relic 計測セットアップ

New Relic Ruby Agentは計測そのものがアプリのオーバーヘッドになるため、ベースラインや最終提出時に常時有効化しない。まず対象アプリと起動方法を確認し、計測が必要な時間だけ有効にして、同じベンチ条件で比較する。

## 手順

### 1. 対象アプリと実行環境を確認する

- `scripts/vars.sh` の `APP_DIR` と `SERVICE_NAME` を問題の実環境に合わせる。
- Rubyのバージョン、Gemfileの有無、Sinatra/Rackのエントリポイント（通常は `config.ru` または `app.rb`）、実際のsystemd unitを確認する。
- アプリプロセスに `RACK_ENV=production`（または `NEW_RELIC_ENV=production`）が渡ることを確認する。New Relicは環境変数から読む設定セクションを決める。

### 2. gemをアプリへ追加する

ローカルのチームリポジトリでGemfileに追加し、lockfileを更新してcommit・pushする。サーバー上でGemfileやlockfileを直接変更しない。

```ruby
gem "newrelic_rpm"
```

### 3. Sinatra/Rackアプリでagentをrequireする

Railsと違い、Sinatra/Rackでは自動requireされないため、アプリの早い段階で一度だけ読み込む。

```ruby
require "newrelic_rpm"
```

`Bundler.require` をアプリが確実に呼んでいる場合は重複requireを避ける。Rack単体アプリで自動計測されない構成の場合だけ、New RelicのRack middleware追加が必要かを公式ドキュメントで確認する。

### 4. `config/newrelic.yml`を作る

対象アプリの `config/` 配下に作る。ライセンスキーはファイルやGitに書かず、環境変数から渡す。

```yaml
common: &default_settings
  app_name: <%= ENV.fetch("NEW_RELIC_APP_NAME", "ISUCON Ruby") %>
  license_key: <%= ENV["NEW_RELIC_LICENSE_KEY"] %>

production:
  <<: *default_settings
  monitor_mode: true
  log_level: info

development:
  <<: *default_settings
  monitor_mode: false
```

既存の `newrelic.yml` がある場合は上書きせず、アプリ名・環境セクション・agentの現行テンプレートとの差分を確認する。YAMLのインデントは2スペースにする。

### 5. キーと有効化設定をアプリプロセスへ渡す

`NEW_RELIC_LICENSE_KEY`、`NEW_RELIC_APP_NAME`、`NEW_RELIC_AGENT_ENABLED=true` を、systemd unitが実際に読み込むEnvironmentFileまたはdrop-inへ設定する。`systemctl cat "$SERVICE_NAME"` で読み込み元を確認してから変更する。

- ライセンスキーを `${SERVER_ID}/env.sh`、`newrelic.yml`、ログ、commitに残さない。
- 既存のGit管理設定に秘密値が入る構成なら、秘密値だけをサーバー上のroot管理ファイルへ移し、unitから参照させる。
- `NEW_RELIC_APP_NAME` はサーバーごとに同じ論理アプリ名を使い、必要ならサーバー識別用の別属性を使う。アプリ名へ秘密情報や短命なベンチIDを含めない。

### 6. 再起動して動作確認する

1. `bundle check` と `ruby -c` / YAMLの構文確認を行う。
2. 対象unitだけを再起動し、起動失敗や502がないことを確認する。
3. 少量のリクエストまたは短いベンチを実行する。
4. アプリの `log/newrelic_agent.log`（設定により別場所）で、`INFO : Reporting to:` が出ていること、エラーやライセンスキー未設定がないことを確認する。
5. 数分待ってNew Relic APMに対象の `app_name` のトランザクションが現れることを確認する。

データが出ない場合は、まず `config/newrelic.yml` の配置、プロセスの環境変数、`RACK_ENV` / `NEW_RELIC_ENV`、unit再起動の有無、agentログの順に確認する。

### 7. 計測後に無効化する

ボトルネック調査が終わったら `NEW_RELIC_AGENT_ENABLED=false`（または設定元からagentを外す）にして再起動する。最終ベンチ前にはNew Relicのログ出力・ネットワーク送信・Gem追加によるオーバーヘッドが残っていないか確認し、`isucon-final-check` の再起動試験を行う。

## 公式資料

- [New Relic Rubyエージェントのインストール](https://docs.newrelic.com/jp/docs/apm/agents/ruby-agent/installation/install-new-relic-ruby-agent/)
- [Ruby agent configuration](https://docs.newrelic.com/docs/apm/agents/ruby-agent/configuration/ruby-agent-configuration/)
- [Ruby agent requirements and supported frameworks](https://docs.newrelic.com/docs/apm/agents/ruby-agent/getting-started/ruby-agent-requirements-supported-frameworks/)
