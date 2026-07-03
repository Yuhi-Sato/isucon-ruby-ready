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

## SSH接続の設定

競技サーバー・練習用EC2ともに、ローカルの `~/.ssh/config` は同じパターンで設定する。エージェントが都度SSHでコマンドを実行する前提（[AGENTS.md](AGENTS.md)参照）のため、接続を使い回すControlMaster設定を必ず入れる。

```bash
mkdir -p ~/.ssh/sockets
```

```
Host s1
  HostName <サーバーのグローバルIP>
  User isucon
  IdentityFile ~/.ssh/<ログインに使う鍵>
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts_isucon
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
```

- `StrictHostKeyChecking accept-new` + 専用の `UserKnownHostsFile`: 競技（練習）のたびにサーバーが新規払い出しされ、過去に使った `~/.ssh/known_hosts` の記録と衝突しがちなので、確認プロンプトなしで新規ホストキーを自動登録しつつ普段使いのknown_hostsは汚さない
- `ServerAliveInterval` / `ServerAliveCountMax`: NAT越しの接続が無通信で切れて`remote-deploy-all`などが固まるのを防ぐ
- `ControlMaster` / `ControlPath` / `ControlPersist`: 初回接続後にマスター接続を600秒使い回すことで、都度`ssh`でコマンドを実行する際の接続確立コストをほぼゼロにする

2台目以降を使う場合は同様のブロックを `Host s2` / `Host s3` として追加する（[Makefileターゲット](#makefileターゲット)の`remote-deploy-s2`等が対象にする）。

## 練習環境の準備（個人練習用）

本番当日はISUCON運営がサーバーを用意するため、この節の作業は不要。**手元でこのリポジトリを練習に使うときのみ**、自分でEC2インスタンスを用意する。

### 1. EC2インスタンスを作成する

- AWSコンソールでパブリックサブネットにEC2インスタンスを作成する（本戦相当のスペックで練習したい場合はインスタンスタイプを合わせる）
- SSH(22)・HTTP(80)など問題で使うポートを許可するセキュリティグループを作成する
- キーペアを新規作成し、秘密鍵（`.pem`）をダウンロードする

### 2. ローカルからのSSH接続を設定する

```zsh
mv ~/Downloads/my_key.pem ~/.ssh/
chmod 400 ~/.ssh/my_key.pem
```

`~/.ssh/config` は[SSH接続の設定](#ssh接続の設定)と同じ形式にする。本番の命名（`s1`）に揃えておくと、`make remote-deploy-s1`などのコマンドが練習でもそのまま使える。

```
Host s1
  HostName <EC2のパブリックIP>
  User ubuntu   # AMIに応じて ec2-user 等に読み替える
  IdentityFile ~/.ssh/my_key.pem
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts_isucon
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
```

```zsh
ssh s1
```

### 3. isucon-ruby-readyをセットアップする

EC2インスタンス内のコードをGit管理するためのSSH鍵生成・GitHubへの登録は手動作業不要。以下の[セットアップ](#セットアップ)のs1手順（tarball展開 → `setup.sh` → `git.sh`）が自動で行う。

- `setup.sh`が呼ぶ`make git-setup`が`~/.ssh/id_ed25519`を生成する（既にあればスキップ）
- `git.sh`がその公開鍵を対象リポジトリのDeploy keyとして登録する（`gh` CLIが認証済みなら自動登録、未認証なら公開鍵を表示して手動登録を待ち受ける）

## セットアップ

### s1（メインサーバー）

競技用サーバーにSSH接続し、ISUCON運営配布リポジトリのディレクトリ直下（`webapp/`と同階層）で以下を実行する。SSHログイン直後のカレントディレクトリがそこと一致するとは限らないため（例: private_isuなど問題によってはログイン直後は別のディレクトリにいる）、まず`webapp/`が見える階層まで`cd`してから実行すること。

```bash
curl -L https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=1

sh setup.sh
sh git.sh {自分たちのチームリポジトリのSSH URL}
```

- `setup.sh`: ツールのインストール・ディレクトリ準備・git設定・サーバー設定の取得を行う
- `git.sh`: `git init`してチームリポジトリをリモートに設定し、初回コミット・pushを行う。あわせてSSH公開鍵のDeploy key登録も行う（`gh` CLIが認証済みなら`gh repo deploy-key add`で自動登録、未認証なら公開鍵を表示して手動登録を待ち受ける）

### s2 / s3（2台目以降）

s1が作成・pushしたチームリポジトリを使う。tarball展開・`git.sh`は行わない。

```bash
git clone {自分たちのチームリポジトリのSSH URL} .
make setup
make set-as-s2   # s3の場合は set-as-s3
make get-conf
```

## デプロイ

### Makefileターゲット

全ターゲットは `make help` で一覧できる。特に運用上の注意が必要なものだけ補足する。

| ターゲット | 用途・注意点 |
|---|---|
| `make bench` | **ベンチマーク実行直前のみ手動で叩く。** ログ削除・設定反映・DB/nginx含む全再起動を伴うため、計測中の他メンバーの作業を壊す |
| `make deploy` | mainマージ時にCIから自動実行される軽量デプロイ。ログは消さず、DB/nginxも再起動しない |
| `make remote-deploy-s1` / `-all` | ローカルから対象サーバー（全サーバー）へ`deploy.sh`をSSH経由で実行する（[ローカルからのデプロイ](#ローカルからのデプロイ手動フォールバック兼用)参照） |
| `make add-profiling-gems` | `bundle add vernier`を実行する。**ローカル専用**（サーバーで実行するとGemfile.lockの変更が残り以後の`git pull`がconflictする） |

### ローカルからのデプロイ（手動フォールバック兼用）

mainマージを待たずに手元からデプロイしたいときや、GitHub ActionsのランナーからサーバーへSSH到達できないときは、ローカルから直接デプロイできる。

```bash
make remote-deploy-s1    # 対象サーバーのみ（remote-deploy-s2 / -s3 も同様）
make remote-deploy-all   # 全サーバーへ並列デプロイ
```

前提として、ローカルの`~/.ssh/config`に各サーバーのHostを[SSH接続の設定](#ssh接続の設定)の形式で`s1` / `s2` / `s3`の名前で定義しておくこと。

- サーバー上の配置パスがホームディレクトリ以外の場合は `make remote-deploy-s1 REMOTE_DEPLOY_PATH=<パス>` で上書きする
- 使わないサーバーがある場合は `make remote-deploy-all SERVERS="s1 s2"` のように対象を絞れる
- `remote-deploy-all` は並列実行（`make -k -j`）のため出力が交錯することがある。失敗したサーバーがあっても残りへ続行し、最後にまとめて報告して非0で終了する

### 必要なGitHub Secrets

CIからの自動デプロイ（`.github/workflows/deploy.yml`）に必要。

| Secret名 | 用途 |
|---|---|
| `SSH_PRIVATE_KEY` | CI専用のSSH秘密鍵（全サーバー共通） |
| `SSH_USER` | SSHユーザー名（通常 `isucon`） |
| `SSH_HOST_S1` / `SSH_HOST_S2` / `SSH_HOST_S3` | 各サーバーのホスト名/IP |
| `DEPLOY_PATH` | サーバー上のリポジトリ配置パス |

s2 / s3を使わない場合は、対応する `SSH_HOST_S2` / `SSH_HOST_S3` を登録しなければそのジョブは自動的にskipされる（`deploy.yml`内で`if: secrets.SSH_HOST_S2 != ''`のように判定している）。ワークフローファイルを編集する必要はない。s1は必須のため常に実行される。

### CI用SSH鍵のセットアップ

1. 手元でCI専用の鍵ペアを作成する（`git-setup`がサーバー上で作るdeploy keyとは別物）
   ```bash
   ssh-keygen -t ed25519 -f ci_deploy_key -N ""
   ```
2. 公開鍵（`ci_deploy_key.pub`）を **各サーバー** の `~/.ssh/authorized_keys` に追記する
3. 秘密鍵（`ci_deploy_key`）の内容をGitHub Secretsの `SSH_PRIVATE_KEY` に登録する

### deploy.shの既知の制約

`deploy.sh` 自身への変更は、その回の `git pull`（`make deploy`内）より前に実行されるため1回のデプロイでは反映されない。反映されるのは次のデプロイから。

## Vernier（サンプリングプロファイラ）の導入

[Vernier](https://github.com/jhawthorn/vernier) はRuby 3.2.1以上が必要。問題のRubyバージョンが古い場合は導入できない。

### gemの追加

**ローカル（手元のリポジトリ）で実行し、`Gemfile` / `Gemfile.lock` の変更をコミット・pushする。** サーバー上で直接実行しないこと（[理由](#makefileターゲット)）。

```bash
make add-profiling-gems
git add Gemfile Gemfile.lock
git commit -m "Add vernier"
git push
```

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
