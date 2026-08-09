# isucon-ruby-ready

ISUCON本番当日に使う「サーバーセットアップ・ログ解析・デプロイ」用ツール一式。
[Yuhi-Sato/isucon-ready](https://github.com/Yuhi-Sato/isucon-ready)（Go版）のRuby版。

このリポジトリは **ツール群のみ** を提供し、ISUCON問題のアプリケーションコード（`webapp/ruby`以下）は含まない。
GitHubの[テンプレートリポジトリ](https://docs.github.com/ja/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)として使い、チームリポジトリを作ってから競技を始める。

## 使い方

### 1. チームリポジトリを作る

```bash
gh repo create <team-repo> --template Yuhi-Sato/isucon-ruby-ready --private --clone
cd <team-repo>
```

作成したcloneが **競技中の作業拠点** になる。以降の作業はすべてここで行う。
`setup.sh`はリポジトリを作らない。push先は`origin`から自動で判別する。

### 2. 接続情報を書く

```bash
cp servers.conf.example servers.conf
```

`servers.conf`はgit管理外（`.gitignore`済み）。書くのはアドレスと鍵だけ。

```sh
S1_HOST=203.0.113.10
S2_HOST=
S3_HOST=

SSH_USER=isucon
SSH_KEY="$HOME/.ssh/isucon.pem"

REMOTE_DIR=/home/isucon

GITHUB_KEY="$HOME/.ssh/id_ed25519"
```

| 変数 | 説明 |
|---|---|
| `S1_HOST` / `S2_HOST` / `S3_HOST` | 各サーバーのグローバルIP。使わないロールは空でよい |
| `SSH_USER` | サーバーへのログインユーザー。**`isucon`である必要がある**（[後述](#ログインユーザーはisuconであること)） |
| `SSH_KEY` | サーバーへのログインに使う秘密鍵。`~/...`はチルダ展開されないので`$HOME`を使う |
| `REMOTE_DIR` | ISUCON運営配布リポジトリのルート（`webapp/`と同階層） |
| `GITHUB_KEY` | GitHub認証用の鍵。**サーバーへのログイン鍵とは別物**（[後述](#github認証ssh-agent-forwarding)） |

> [!WARNING]
> **`REMOTE_DIR`が配布リポジトリのルートと一致するか必ず確認すること。**
> ISUCON運営配布リポジトリのルート（`webapp/`と同階層）が`/home/isucon`直下でない問題がある（例: private_isuは`/home/isucon/private_isu`が本当のルート）。サーバーに一度SSHして`ls /home/isucon`し、`webapp/`が直下に見えない場合は`REMOTE_DIR`を実際のパスに変えること。
>
> 間違えると、ツール一式が実際のアプリコードと無関係な場所に展開され、`scripts/vars.sh`の`APP_DIR`/`SERVICE_NAME`が噛み合わないまま**エラーも出さずにセットアップが「完了」してしまう**。

### 3. セットアップする

```bash
./setup.sh          # s1（引数なしのときはs1）
./setup.sh s2       # 2台目以降。s1の完了後に実行する
./setup.sh s3
```

`setup.sh`は**ローカルマシン**（サーバーではない）から実行する。行うことは4つ。

1. `origin`からチームリポジトリを判別し、`servers.conf`を読む
2. ローカルからGitHubへのSSH認証を確認する（ここが通らなければサーバーには触らない）
3. `~/.ssh/config`に`Host s1`/`s2`/`s3`の[管理ブロックを生成](#ssh接続の設定)する
4. サーバーにSSHして`remote-setup.sh`を実行する
   - チームリポジトリの`main`を取得し、配布アプリコードの上にツール一式を被せる
   - `sh server-setup.sh <role>`（ツール導入・`make set-as-<role>`・`make get-conf`）
   - **s1のみ**: 配布アプリコードをコミットして`git push`する

何度実行しても安全（冪等）。s2/s3はs1がpushしたmainを取得するため、**必ずs1を先に完了させること**。

s1の完了後、ローカルにアプリコードを取り込む。

```bash
git pull
```

以降は[isucon-initial-recon](.claude/skills/isucon-initial-recon/SKILL.md)スキルの初動調査に進む。サーバーへのSSHは`make bench-prep`/`make alp`/`make slow-query`など**サーバー上でしか実行できない操作**に限定し、コードや設定の編集はこのローカルcloneで行ってからpushする。

> [!IMPORTANT]
> **サーバーは`origin/main`からツール一式を取得する。**
> ローカルで`scripts/vars.sh`や`tool-config/`を調整した場合、**pushしてからでないとサーバーに反映されない**。`./setup.sh`を実行する前に`git push`しておくこと。

## GitHub認証（ssh agent forwarding）

サーバーからGitHubへの認証は **ssh agent forwarding** で行う。ローカルの`ssh-agent`に載せた鍵をサーバーへ転送し、サーバー上のgitはそれを使う。**サーバー上に鍵は作らない。**

`setup.sh`が生成する`~/.ssh/config`の管理ブロックに`ForwardAgent yes`が入るため、セットアップ時だけでなく、以後の`make deploy` / `make bench-prep`の先頭で走る`git pull`もそのまま動く。

### 前提

- ローカルで`ssh-agent`が動いていること。`ssh-add -l`に鍵が出なければ`servers.conf`の`GITHUB_KEY`を`setup.sh`が自動で`ssh-add`する
- その鍵がGitHubの **Settings > SSH and GPG keys** に登録されていること

`setup.sh`はサーバーに触る前にローカルで`ssh -T git@github.com`を実行して両方を確認する。通らなければそこで止まる。

### 制約

- **転送なしのセッションからは`git pull`が失敗する。** cronや、`ForwardAgent`を無効にしてログインしたシェルから`make deploy`を叩くと認証できない。デプロイは`make remote-deploy-s1`（ローカルから実行）か、通常どおり`ssh s1`でログインしたシェルから行うこと
- 転送中のagentは、接続している間そのサーバーのroot権限者から利用できる。チーム専有のサーバーである前提で許容している

### ログインユーザーは`isucon`であること

`SSH_USER`が`isucon`でない場合、`setup.sh`はエラーで停止する。`sudo -u isucon`で回避することはしない。`sudo`は`SSH_AUTH_SOCK`を落とすうえ、ソケット自体がログインユーザー所有の`0600`なので`isucon`からは読めず、agent forwardingと両立しないため。

練習環境などで`ubuntu`でしか入れない場合は、サーバー上で`isucon`の`~/.ssh/authorized_keys`に自分の公開鍵を追加してから`SSH_USER=isucon`にする。

```bash
# サーバー上（ubuntu等でログインした状態）
sudo mkdir -p /home/isucon/.ssh
sudo cp ~/.ssh/authorized_keys /home/isucon/.ssh/authorized_keys
sudo chown -R isucon:isucon /home/isucon/.ssh
sudo chmod 700 /home/isucon/.ssh && sudo chmod 600 /home/isucon/.ssh/authorized_keys
```

`make remote-deploy-s1`もログインユーザーのまま`deploy.sh`を実行するため、どのみち`isucon`でのログインが必要になる。

## SSH接続の設定

`~/.ssh/config`は`setup.sh`が`servers.conf`から自動生成する。手で書く必要はない。生成される内容は次のとおり。

```
# >>> isucon-ruby-ready managed block >>>
Host s1
  HostName 203.0.113.10
  User isucon
  IdentityFile /Users/you/.ssh/isucon.pem
  IdentitiesOnly yes
  ForwardAgent yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts_isucon
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
# <<< isucon-ruby-ready managed block <<<
```

- `ForwardAgent`: サーバー上のgitがローカルのssh-agentを使うための転送設定（[前述](#github認証ssh-agent-forwarding)）
- `IdentitiesOnly`: agentに鍵が多いと`Too many authentication failures`でログインが弾かれるため、ログインには`IdentityFile`だけを使わせる
- `StrictHostKeyChecking accept-new` + 専用の`UserKnownHostsFile`: 競技（練習）のたびにサーバーが新規払い出しされ、過去に使った`~/.ssh/known_hosts`の記録と衝突しがちなので、確認プロンプトなしで新規ホストキーを自動登録しつつ普段使いのknown_hostsは汚さない
- `ServerAliveInterval` / `ServerAliveCountMax`: NAT越しの接続が無通信で切れて`remote-deploy-all`などが固まるのを防ぐ
- `ControlMaster` / `ControlPath` / `ControlPersist`: 初回接続後にマスター接続を600秒使い回すことで、都度`ssh`でコマンドを実行する際の接続確立コストをほぼゼロにする（エージェントが都度SSHでコマンドを実行する前提のため。[CLAUDE.md](CLAUDE.md)参照）

補足:

- 管理ブロックは**ファイルの先頭**に挿入される。sshは各オプションで最初に得られた値を採用するため、末尾に追記すると既存の`Host *`の設定に負けるため
- 実行のたびに管理ブロックは書き直される。ブロック内を手で編集しても次回実行で消える
- 実行前の`~/.ssh/config`は`~/.ssh/config.isucon-bak`に退避される
- 管理ブロックの**外**に`Host s1`などが残っていると、そちらが先に現れた場合に優先される。`setup.sh`が検出して警告するので、古い定義は消すこと

## 練習環境の準備（個人練習用）

本番当日はISUCON運営がサーバーを用意するため、この節の作業は不要。**手元でこのリポジトリを練習に使うときのみ**、自分でEC2インスタンスを用意する。

1. AWSコンソールでパブリックサブネットにEC2インスタンスを作成する（本戦相当のスペックで練習したい場合はインスタンスタイプを合わせる）
2. SSH(22)・HTTP(80)など問題で使うポートを許可するセキュリティグループを作成する
3. キーペアを新規作成し、秘密鍵（`.pem`）をダウンロードする

```bash
mv ~/Downloads/my_key.pem ~/.ssh/
chmod 400 ~/.ssh/my_key.pem
```

`servers.conf`の`SSH_KEY`にこの`.pem`を指定する。AMIによっては初期状態で`isucon`ユーザーが存在しないため、[ログインユーザーは`isucon`であること](#ログインユーザーはisuconであること)の手順で`isucon`にログインできるようにしてから`./setup.sh`を実行する。

## 途中で失敗した場合の再開

`setup.sh`がサーバー側処理の途中で失敗した場合は、サーバー上で`remote-setup.sh`を単体実行して途中から再開できる。冪等なので何度実行しても安全。

```bash
ssh -A s1                                        # agent転送付きでログインする
cd /home/isucon                                  # 配布リポジトリのルート
bash remote-setup.sh s1 <owner>/<repo>           # s2/s3の場合は s2 / s3
```

サーバー上にまだ`remote-setup.sh`が無い（1回目のセットアップが早い段階で失敗した）場合は、テンプレート本体から取得する。チームリポジトリはprivateなのでこちらのURLを使う。

```bash
curl -fsSL https://raw.githubusercontent.com/Yuhi-Sato/isucon-ruby-ready/main/remote-setup.sh \
  | bash -s -- s1 <owner>/<repo>   # ルートが異なる場合は --dir <path> を追加
```

`ssh -A`を忘れると認証に失敗する。その場合は何を確認すべきかをスクリプトが表示して止まる。

## デプロイ

### Makefileターゲット

Makefileはターゲット名のショートカット集で、ロジックは`scripts/`以下のシェルスクリプトにある（問題によって変わる変数は`scripts/vars.sh`に集約）。全ターゲットは `make help` で一覧できる。特に運用上の注意が必要なものだけ補足する。

| ターゲット | 用途・注意点 |
|---|---|
| `make bench-prep` | **ベンチマーク実行直前のみ手動で叩く。** ログ削除・設定反映・DB/nginx含む全再起動を伴うため、計測中の他メンバーの作業を壊す |
| `make deploy` | サーバー上で手動実行する軽量デプロイ（`deploy.sh`と同じ。git pull→bundle install→アプリのデーモン再起動）。ログは消さず、DB/nginxも再起動しない |
| `make remote-deploy-s1` / `-all` | ローカルから対象サーバー（全サーバー）へ`deploy.sh`をSSH経由で実行する（[ローカルからのデプロイ](#ローカルからのデプロイ)参照） |
| `make add-profiling-gems` | `bundle add vernier`を実行する。**ローカル専用**（サーバーで実行するとGemfile.lockの変更が残り以後の`git pull`がconflictする） |

### ローカルからのデプロイ

変更をpushしたら、ローカルから各サーバーへ直接デプロイする。

```bash
make remote-deploy-s1    # 対象サーバーのみ（remote-deploy-s2 / -s3 も同様）
make remote-deploy-all   # 全サーバーへ並列デプロイ
```

対象は`~/.ssh/config`の`Host s1`/`s2`/`s3`で、`setup.sh`が生成済み。デプロイ先のパスは`servers.conf`の`REMOTE_DIR`から自動で読む。

- 一時的に別パスへ向けたい場合は `make remote-deploy-s1 REMOTE_DEPLOY_PATH=<パス>` で上書きする
- 使わないサーバーがある場合は `make remote-deploy-all SERVERS="s1 s2"` のように対象を絞れる
- `remote-deploy-all` は並列実行（`make -k -j`）のため出力が交錯することがある。失敗したサーバーがあっても残りへ続行し、最後にまとめて報告して非0で終了する

### deploy.shの既知の制約

`deploy.sh` はエントリポイント（env読み込み→`git pull`→`scripts/deploy.sh`への委譲）に徹しており、デプロイロジック本体（bundle install・デーモン再起動）は `scripts/deploy.sh` にある。後者はpull済みの最新版が実行されるため変更が同じデプロイで反映されるが、**`deploy.sh` 自身への変更だけは `git pull` より前に読み込まれるため1回のデプロイでは反映されない**。反映されるのは次のデプロイから。

## Vernier（サンプリングプロファイラ）の導入

gem追加・Rack middlewareへの組み込み・CLIでの単発プロファイリング・プロファイルの読み方は[isucon-vernier-profiling](.claude/skills/isucon-vernier-profiling/SKILL.md)スキルを参照。

## N+1検出の運用

ISUCON公式のRuby参考実装は近年一貫してSinatra + mysql2（またはpg）を直接使う構成であり、ActiveRecordを前提とするN+1検出gem（Prosopiteなど）は検出対象のイベントが流れず機能しない。そのため本リポジトリではN+1検出をgemに頼らず、performance_schemaのクエリダイジェスト集計で代用する。

```bash
make slow-query
```

`make slow-query` の出力の `calls` 列（同一クエリパターンの実行回数）を見て、リクエスト数に対して極端に多いクエリがあればN+1を疑う。
