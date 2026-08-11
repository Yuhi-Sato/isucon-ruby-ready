# isucon-ruby-ready

ISUCONで利用するツール一式

## 使い方

### 1. チームリポジトリを作る

本リポジトリをテンプレートリポジトリとして、チームリポジトリを作成する。以降の作業は作成したリポジトリ以下で行う。

```bash
gh repo create <team-repo> --template Yuhi-Sato/isucon-ruby-ready --private --clone
cd <team-repo>
```

### 2. SSH　を設定する

#### サーバーへのログイン

`HostName` / `IdentityFile` を自分の環境に合わせて`~/.ssh/config`に書く。`s2` / `s3`も同じ形で足す。`ControlPath`用に`mkdir -p ~/.ssh/sockets`しておく。

```
Host s1
  HostName <fuga>
  User isucon
  IdentityFile ~/.ssh/<hoge>.pem
  IdentitiesOnly yes
  ForwardAgent yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts_isucon
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
```

練習環境などで`ubuntu`でしか入れない場合は、サーバー上で`isucon`の`~/.ssh/authorized_keys`に公開鍵を追加する。

```bash
# サーバー上（ubuntu等でログインした状態）
sudo mkdir -p /home/isucon/.ssh
sudo cp ~/.ssh/authorized_keys /home/isucon/.ssh/authorized_keys
sudo chown -R isucon:isucon /home/isucon/.ssh
sudo chmod 700 /home/isucon/.ssh && sudo chmod 600 /home/isucon/.ssh/authorized_keys
```

#### サーバーからGitHubへの認証（agent forwarding）

ローカルの`ssh-agent`に載せた鍵を`ForwardAgent`で転送し、サーバー上のgitがそれを使う。

1. GitHub用の鍵をagentに載せる（`ssh-add -l`で確認。無ければ`ssh-add ~/.ssh/<鍵>`）
2. その公開鍵をGitHubの **Settings > SSH and GPG keys** に登録する
3. ローカルで`ssh -T git@github.com`が通ることを確認する
4. 上記の`~/.ssh/config`に`ForwardAgent yes`があること

### 3. セットアップする
サーバー上で以下を実行し、本リポジトリのコードを引っ張る

```bash
cd /home/isucon   # webapp/ がある配布ルート
git init -b main
git remote add origin git@github.com:<repo-owner>/<repo-name>.git
git fetch origin main
git checkout -f -B main origin/main
```

## 練習環境の準備（個人練習用）

本番当日はISUCON運営がサーバーを用意するため、この節の作業は不要。**手元でこのリポジトリを練習に使うときのみ**、自分でEC2インスタンスを用意する。

1. AWSコンソールでパブリックサブネットにEC2インスタンスを作成する（本戦相当のスペックで練習したい場合はインスタンスタイプを合わせる）
2. SSH(22)・HTTP(80)など問題で使うポートを許可するセキュリティグループを作成する
3. キーペアを新規作成し、秘密鍵（`.pem`）をダウンロードする

```bash
mv ~/Downloads/my_key.pem ~/.ssh/
chmod 400 ~/.ssh/my_key.pem
```

`IdentityFile`にこの`.pem`を指定する。AMIによっては初期状態で`isucon`ユーザーが存在しないため、[サーバーへのログイン](#サーバーへのログイン)どおり`isucon`に入れるようにしてから`./setup.sh`を実行する。

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

対象は`~/.ssh/config`の`Host s1`/`s2`/`s3`（[手順2](#2-sshを設定する)で設定）。デプロイ先のパスはデフォルトで`/home/isucon`。

- 一時的に別パスへ向けたい場合は `make remote-deploy-s1 REMOTE_DEPLOY_PATH=<パス>` で上書きする
- 使わないサーバーがある場合は `make remote-deploy-all SERVERS="s1 s2"` のように対象を絞れる
- `remote-deploy-all` は並列実行（`make -k -j`）のため出力が交錯することがある。失敗したサーバーがあっても残りへ続行し、最後にまとめて報告して非0で終了する
