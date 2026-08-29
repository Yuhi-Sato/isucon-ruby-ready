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
サーバー上で以下を実行し、本リポジトリのコードを引っ張ったあと `make setup-sN` でツール導入・`SERVER_ID` 設定・実際のDB/nginx設定と`env.sh`の取得（`sN/`配下、`make get-conf`相当）・初回commit&pushまで行う（`s2` / `s3` も同様）。

```bash
cd /home/isucon   # webapp/ がある配布ルート
git init -b main
git remote add origin git@github.com:<repo-owner>/<repo-name>.git
git fetch origin main
git checkout -f -B main origin/main

make setup-s1     # s2 なら make setup-s2
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

`IdentityFile`にこの`.pem`を指定する。AMIによっては初期状態で`isucon`ユーザーが存在しないため、[サーバーへのログイン](#サーバーへのログイン)どおり`isucon`に入れるようにしてから`make setup-s1`を実行する。

## デプロイ
原則はローカルから実行する

対象は `~/.ssh/config` の `Host s1` / `s2` / `s3`（[手順2](#2-sshを設定する)）。デプロイ先パスのデフォルトは `/home/isucon`（別パスなら `REMOTE_DEPLOY_PATH=<パス>` で上書き）。

### アプリコードの反映

```bash
make remote-deploy-s1     # s2 / s3 も同様
make remote-deploy-all    # 全サーバーへ並列（SERVERS="s1 s2" で絞れる）
```

サーバー上にいるときは `make deploy`（`git pull` → `scripts/deploy.sh`）。

### 設定ファイル（`sN/` 以下）の反映

`s1/etc/mysql`・`s1/etc/nginx`・`s1/env.sh` などを変えたとき。

```bash
make remote-deploy-conf-s1
```

### ベンチ直前

`make bench-prep` は `git pull` → `bundle install` → ログ消去 → `deploy-conf` → DB / アプリ / nginx の全再起動までまとめて行う。

```bash
make remote-bench-prep-s1
```

## 練習環境をHTTPS化する（自己署名証明書）

練習用サーバー上で、アクセスに使うホスト名またはIPアドレスを指定して実行する。

```bash
make self-signed-cert CERT_HOST=isucon.example.test
# 既存の証明書を作り直す場合
make self-signed-cert CERT_HOST=isucon.example.test FORCE=1
```

証明書は `/etc/ssl/certs/isucon-self-signed.crt`、秘密鍵は
`/etc/ssl/private/isucon-self-signed.key` に作られる。秘密鍵は root のみ読み取り可能で、
`make get-conf` の収集対象外にしてある。

対象の Nginx `server {}` ブロックに次の1行を追加する。HTTPも残す場合は既存の
`listen 80;` と併記できる。

```nginx
include snippets/isucon-self-signed-ssl.conf;
```

生成スクリプトはスニペットを `/etc/nginx/snippets/isucon-self-signed-ssl.conf` に配置し、
`nginx -t` に成功した場合は起動中の Nginx を reload する。証明書の生成後に上記の
`include` を追加した場合は、設定反映のため次も実行する。

```bash
sudo nginx -t && sudo systemctl reload nginx
```

自己署名証明書なので、ブラウザやベンチクライアント側では信頼設定を追加するか、
検証を無効化する必要がある。
