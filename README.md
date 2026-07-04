# isucon-ruby-ready

ISUCON本番当日に使う「サーバーセットアップ・ログ解析・デプロイ」用ツール一式。
[Yuhi-Sato/isucon-ready](https://github.com/Yuhi-Sato/isucon-ready)（Go版）のRuby版。

このリポジトリは **ツール群のみ** を提供し、ISUCON問題のアプリケーションコード（`webapp/ruby`以下）は含まない。
ISUCON運営配布リポジトリのルートに、このリポジトリの内容を展開して使う。

設計の背景・意図は [docs/superpowers/specs/2026-07-01-isucon-ruby-ready-design.md](docs/superpowers/specs/2026-07-01-isucon-ruby-ready-design.md)、セットアップフロー統合・CI変数化の経緯は [docs/superpowers/specs/2026-07-04-setup-flow-unification.md](docs/superpowers/specs/2026-07-04-setup-flow-unification.md) を参照。

## 当日チェックリスト

セットアップ後、最初に以下を問題に合わせて確認・修正する。`APP_DIR`確認やクエリ抽出など問題固有の適応は [isucon-initial-recon](.agents/skills/isucon-initial-recon/SKILL.md) スキルの初動調査で行う（`make extract-sql`はそちらの手順に含まれる）。

- [ ] `Makefile` の `SERVICE_NAME` を問題のサービス名に変更する（例: `isupipe-ruby.service`）
- [ ] `Makefile` の `APP_DIR` を確認する（`webapp/ruby` 以外の構成の場合）
- [ ] `Makefile` の `DB_SERVICE_NAME` を確認する（MariaDBの場合は `mariadb` 等に変更）
- [ ] `git-setup` 内の `git config` の `user.email` / `user.name` を確認する
- [ ] GitHub Secrets / Variablesを登録する（[必要なGitHub Secrets / Variables](#必要なgithub-secretsvariables)、[CI用SSH鍵のセットアップ](#ci用ssh鍵のセットアップ)を参照）
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

チームリポジトリの作成とDeploy keyの登録はローカルの`gh` CLIで自動化されている（以下の[セットアップ](#セットアップ)のs1手順を参照）。事前にローカルマシンで`gh auth login`を済ませておく。

## セットアップ

> [!WARNING]
> **実行前に、配布リポジトリのルートが`/home/isucon`と一致するか必ず確認すること。**
> ISUCON運営配布リポジトリのルート（`webapp/`と同階層）が`/home/isucon`直下でない問題がある（例: private_isuは`/home/isucon/private_isu`が本当のルート）。サーバーに一度SSHして`ls /home/isucon`し、`webapp/`が直下に見えない場合は`--dir`を省略せず必ず指定すること（[配布リポジトリのルートが異なる場合](#配布リポジトリのルートが異なる場合private_isuなど)参照）。
>
> `--dir`を付け忘れると、ツール一式が実際のアプリコードと無関係な場所に展開され、`Makefile`の`APP_DIR`/`SERVICE_NAME`が噛み合わないまま**エラーも出さずにセットアップが「完了」してしまう**。

`setup.sh`1コマンドで、Deploy keyの生成・登録、tarball展開・サーバー側ツールセットアップ・チームリポジトリへのgit配線までを行う。**ローカルマシン**（サーバーではない）から実行する。

GitHubへの認証は、サーバーごとに自動生成する**Deploy key**（対象リポジトリ限定・書き込み権限付きの鍵、`~/.ssh/github_deploy_<repo-name>`）で行う。鍵の登録はローカルの`gh` CLIが自動で行うため、事前に`gh auth login`を済ませておく（**s1/s2/s3すべての実行で必要**）。鍵ファイル名にリポジトリ名を含むのは、Deploy keyがGitHub全体で1つのリポジトリにしか登録できず、競技をまたいだ鍵の使い回しが衝突するため。

かつてのssh agent forwarding（`ssh -A`）方式は、sudoでのユーザー切り替えで転送が失われる等実運用で不安定なうえ、サーバー上の`git pull`（`make deploy` / `make bench`の先頭）がforwarding無しでは動かないため廃止した（経緯は[2026-07-04-setup-flow-unification.md](docs/superpowers/specs/2026-07-04-setup-flow-unification.md)の改訂節を参照）。

### s1（メインサーバー、チームリポジトリの作成元）

```bash
./setup.sh <user@server> [repo-name]
```

- `<user@server>`: `~/.ssh/config`に設定した`s1`など、または`isucon@<IPアドレス>`
- `[repo-name]`: チームリポジトリ名（オーナーは`Yuhi-Sato`固定）。省略時は`ISUCON-<実行時刻>`（例: `ISUCON-20260704153000`）を新規採番する

`setup.sh`が（s1の場合に）行うこと:
1. ローカルの前提チェック（`gh auth status`）
2. リポジトリが存在しなければ`gh repo create --private`で作成
3. サーバー上にDeploy key（`~/.ssh/github_deploy_<repo-name>`）が無ければ生成し、ローカルの`gh repo deploy-key add --allow-write`でリポジトリに登録
4. sshでサーバーへ接続し、その中で以下を完結させる
   - ISUCON運営配布リポジトリのルート（`--dir`で指定。省略時は`/home/isucon`）へこのリポジトリのtarballを展開
   - `sh server-setup.sh s1`（ツールのインストール・ディレクトリ準備・git設定・サーバー設定の取得）
   - `git init` → `origin`設定 → `core.sshCommand`にDeploy keyを固定（以後の`git pull`も追加設定なしで動く） → 初回コミット → `git push -u origin main`

2回目以降の実行や別サーバーに対する再実行もそのまま行える（冪等）。ただし`repo-name`を省略すると実行のたびに新しい名前が採番されるため、**同じリポジトリに対して再実行する場合は最初に採番された`repo-name`を明示的に指定すること**（s2/s3向けにも同じ名前を使う）。

### s2 / s3（2台目以降）

s1が作成・pushしたチームリポジトリの`repo-name`を明示して、同じ`setup.sh`を実行する。

```bash
./setup.sh <user@server> <repo-name>
```

`setup.sh`が（s2/s3の場合に）行うこと:
1. s1と同様にサーバー上でDeploy keyを生成し、`gh repo deploy-key add --allow-write`で登録する
2. サーバー上の配布リポジトリルート（`--dir`。省略時は`/home/isucon`）には、ISUCON運営配布のアプリコード（`webapp/`等）が既に置かれている（非空）。`git clone`は非空ディレクトリを拒否するため使わず、代わりに`git init` → `remote add` → `core.sshCommand`固定 → `git fetch origin main` → `git checkout -f -B main origin/main`でチームリポジトリの内容（Makefile・tool-config・webapp含む）を被せる
3. `sh server-setup.sh s2`（s3の場合は`s3`）でツール導入・`make set-as-s2`・`make get-conf`まで行う

### 役割（s1/s2/s3）の指定方法

`<user@server>`が`~/.ssh/config`の`Host s1`/`s2`/`s3`のエイリアスならそこから役割を自動推定する。`isucon@<IPアドレス>`のように推定できない指定をする場合は`--role`で明示する。

```bash
./setup.sh isucon@203.0.113.10 my-repo --role s2
```

### 配布リポジトリのルートが異なる場合（private_isuなど）

SSHログイン直後のカレントディレクトリが、ISUCON運営配布リポジトリのルート（`webapp/`と同階層）と一致しない問題がある（例: private_isu）。その場合は`--dir`で実際のルートパスを指定する。

```bash
./setup.sh s1 my-repo --dir /home/isucon/private_isu
```

### ローカル経由が使えない場合のフォールバック

`gh`が使えないなど、ローカルからの1コマンドが使えない場合は、サーバーに直接SSHして手動で行う。

```bash
# サーバー上（配布リポジトリのルートで）
curl -L https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=1
sh server-setup.sh s1   # s2/s3の場合は s2 / s3
```

この場合、チームリポジトリへのgit初期化・push（s1）やgit配線（s2/s3）、Deploy keyの生成・登録は別途手動で行う必要がある。

### セットアップ後: ここからの作業拠点

> [!IMPORTANT]
> **`setup.sh`完了後は、この`isucon-ruby-ready`ではなく、s1がpushしたチームリポジトリをローカルにcloneしたディレクトリが以後の作業拠点になる。**
> `isucon-ruby-ready`はツール一式のテンプレートにすぎない。Makefile変数の調整・`tool-config/alp/config.yml`編集・アプリコードの確認などは全てチームリポジトリ側で行う（[AGENTS.md](AGENTS.md)の「サーバーのワーキングツリーを直接編集しない。変更はローカル→push→デプロイの流れで反映する」という前提）。

```bash
gh repo clone Yuhi-Sato/<repo-name>
cd <repo-name>
```

以降は[isucon-initial-recon](.agents/skills/isucon-initial-recon/SKILL.md)スキルの初動調査に進む。サーバーへのSSHは、`systemctl`でのサービス名確認・DBスキーマ確認・`make bench`/`make alp`/`make slow-query`など**サーバー上でしか実行できない操作**に限定し、コードや設定の編集はこのローカルcloneで行ってからpushする。

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

### 必要なGitHub Secrets/Variables

CIからの自動デプロイ（`.github/workflows/deploy.yml`）に必要。ホスト名やパスなど秘密情報でないものは、ジョブレベルの`if`条件から参照できる **Variables** に登録する（`secrets`コンテキストはジョブレベルの`if`から参照できず常に空文字扱いになるため、Secretsに置くとs2/s3の自動skipが機能しない）。

| Secret名 | 用途 |
|---|---|
| `SSH_PRIVATE_KEY` | CI専用のSSH秘密鍵（全サーバー共通） |

| Variable名 | 用途 |
|---|---|
| `SSH_USER` | SSHユーザー名（通常 `isucon`） |
| `SSH_HOST_S1` / `SSH_HOST_S2` / `SSH_HOST_S3` | 各サーバーのホスト名/IP |
| `DEPLOY_PATH` | サーバー上のリポジトリ配置パス |

s2 / s3を使わない場合は、対応する `SSH_HOST_S2` / `SSH_HOST_S3`（Variable）を登録しなければそのジョブは自動的にskipされる（`deploy.yml`内で`if: vars.SSH_HOST_S2 != ''`のように判定している）。ワークフローファイルを編集する必要はない。s1は必須のため常に実行される。

### CI用SSH鍵のセットアップ

1. 手元でCI専用の鍵ペアを作成する（`setup.sh`がサーバーごとに生成・登録するGitHub用Deploy keyとは別物。CIがサーバーにSSHログインするための鍵）
   ```bash
   ssh-keygen -t ed25519 -f ci_deploy_key -N ""
   ```
2. 公開鍵（`ci_deploy_key.pub`）を **各サーバー** の `~/.ssh/authorized_keys` に追記する
3. 秘密鍵（`ci_deploy_key`）の内容をGitHub Secretsの `SSH_PRIVATE_KEY` に登録する

### deploy.shの既知の制約

`deploy.sh` 自身への変更は、その回の `git pull`（`make deploy`内）より前に実行されるため1回のデプロイでは反映されない。反映されるのは次のデプロイから。

## Vernier（サンプリングプロファイラ）の導入

gem追加・Rack middlewareへの組み込み・CLIでの単発プロファイリング・プロファイルの読み方は[isucon-vernier-profiling](.agents/skills/isucon-vernier-profiling/SKILL.md)スキルを参照。

## N+1検出の運用

ISUCON公式のRuby参考実装は近年一貫してSinatra + mysql2（またはpg）を直接使う構成であり、ActiveRecordを前提とするN+1検出gem（Prosopiteなど）は検出対象のイベントが流れず機能しない。そのため本リポジトリではN+1検出をgemに頼らず、performance_schemaのクエリダイジェスト集計で代用する。

```bash
make slow-query
```

`make slow-query` の出力の `calls` 列（同一クエリパターンの実行回数）を見て、リクエスト数に対して極端に多いクエリがあればN+1を疑う。
