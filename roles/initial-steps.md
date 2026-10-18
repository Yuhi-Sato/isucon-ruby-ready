# 初動手順（TODOリスト）

競技開始直後の初動を、担当者ごとの手順とTODOにまとめたもの。完了したらチェックする。

| 担当 | GitHub | やること |
| --- | --- | --- |
| Yuhi-Sato | [Yuhi-Sato](https://github.com/Yuhi-Sato) | リポジトリ作成、AWS構築、秘密鍵共有、テスト、構成図 |
| u-ktk | [u-ktk](https://github.com/u-ktk) | マニュアルの読み込み |
| garebare | [garebareDA](https://github.com/garebareDA) | サービス名設定、ベンチ実行、計測設定 |

## 全体の流れ

```
[Yuhi-Sato] 前日まで: リポジトリ作成
     ↓
[Yuhi-Sato] 当日: AWS構築 → インスタンス作成 → 秘密鍵共有 → サーバーに展開（make setup-s1）
     ↓
 ├─ [Yuhi-Sato] isucon-ruby-testing / update-architecture-diagram
 ├─ [u-ktk]     マニュアルを読み込む
 └─ [garebare]  サービス名設定 → ベンチ実行 → 計測設定
```

- garebareは、Yuhi-Satoの「秘密鍵共有」と「サーバーへの展開」が済むまで作業を始められない
- u-ktkのマニュアル読み込みは、鍵共有を待たずに最初から始められる

---

## Yuhi-Sato

### ISUCON前日まで

- [ ] チームリポジトリを作成する
  ```bash
  gh repo create <team-repo> --template Yuhi-Sato/isucon-ruby-ready --private --clone
  ```

### 当日（最優先。他メンバーがこれ待ち）

#### AWS構築・秘密鍵共有

- [ ] AWSコンソールでパブリックサブネットにEC2インスタンスを作成する（本戦相当のスペックならインスタンスタイプを合わせる）
- [ ] SSH(22)・HTTP(80)など問題で使うポートを許可するセキュリティグループを作成する
- [ ] キーペアを新規作成し、秘密鍵（`.pem`）をダウンロードする
  ```bash
  mv ~/Downloads/my_key.pem ~/.ssh/
  chmod 400 ~/.ssh/my_key.pem
  ```
- [ ] 秘密鍵（`.pem`）をメンバーに共有する

#### サーバーへ入れるようにする

- [ ] `~/.ssh/config`に`Host s1`を書く（`HostName` / `IdentityFile`を自分の環境に合わせる。`s2` / `s3`も同様）
- [ ] `mkdir -p ~/.ssh/sockets`する（`ControlPath`用）
- [ ] `ssh s1`で`isucon`ユーザーとして入れることを確認する
  - 初期状態で`isucon`に入れないAMIでは、`ubuntu`でログインして`isucon`の`~/.ssh/authorized_keys`に公開鍵を追加する
    ```bash
    sudo mkdir -p /home/isucon/.ssh
    sudo cp ~/.ssh/authorized_keys /home/isucon/.ssh/authorized_keys
    sudo chown -R isucon:isucon /home/isucon/.ssh
    sudo chmod 700 /home/isucon/.ssh && sudo chmod 600 /home/isucon/.ssh/authorized_keys
    ```

#### サーバーからGitHubへの認証（agent forwarding）

- [ ] GitHub用の鍵をagentに載せる（`ssh-add -l`で確認。無ければ`ssh-add ~/.ssh/<鍵>`）
- [ ] その公開鍵をGitHubの Settings > SSH and GPG keys に登録する
- [ ] ローカルで`ssh -T git@github.com`が通ることを確認する
- [ ] `~/.ssh/config`に`ForwardAgent yes`があることを確認する

#### リポジトリをサーバーに展開する

ローカルから`isucon-remote-setup`スキルを実行すれば、以下の2項目をs1→s2→s3の順にSSH越しで流せる。手作業で行う場合は次のとおり。

- [ ] サーバー上で本リポジトリのコードを引っ張る
  ```bash
  cd /home/isucon   # webapp/ がある配布ルート
  git init -b main
  git remote add origin git@github.com:<repo-owner>/<repo-name>.git
  git fetch origin main
  git checkout -f -B main origin/main
  ```
- [ ] `make setup-s1`を実行する（ツール導入・`SERVER_ID`設定・DB/nginx設定と`env.sh`の取得・初回commit&pushまで。`s2` / `s3`もあれば同様）
- [ ] 初回commit&pushがチームリポジトリに反映されたことを確認する
- [ ] メンバーに展開完了を伝える（garebareDAがここから始められる）

### 展開後

- [ ] `isucon-ruby-testing`を実行する（リファクタ前の回帰テスト環境を作る）
- [ ] `update-architecture-diagram`を実行する（サーバ構成・通信経路の図をmermaidで描く）

---

## u-ktk

- [ ] マニュアルを読み込む
- [ ] マニュアルの本文を`docs/manual.md`に保存し、mainにcommit・pushする（`isucon-score-strategy`がスコア式の根拠として参照する。競技開始時に1回）
  ```bash
  git add docs/manual.md
  git commit -m "docs: 問題マニュアルを追加"
  git pull --rebase origin main && git push origin main
  ```

---

## garebare

Yuhi-Satoがリポジトリをサーバーに展開してから始める。順序には意味があるので、上から順に進める。

- [ ] `isucon-service-name-setup`を実行する
  - `scripts/vars.sh`の`SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME`を実サーバーに合わせる
  - ズレたままベンチを回すと古いアプリを計測してしまうため、最優先
- [ ] ベンチマークを実行する
  - [ ] ローカルで、ポータルの結果を標準入力に渡して`make save-bench-log`を実行する（例: `pbpaste | make save-bench-log`。`docs/bench/`に保存してcommitする。pushはしない）
  - [ ] ベンチ結果はポータルサイトで確認する
- [ ] `isucon-measurement-setup`を実行する

---

## 初動の完了条件

- [ ] Yuhi-Sato: インスタンスを作成し、秘密鍵を共有し、リポジトリをサーバーに展開した（`make setup-s1`まで）
- [ ] Yuhi-Sato: `isucon-ruby-testing`と`update-architecture-diagram`を実行した
- [ ] u-ktk: マニュアルを読み込み、`docs/manual.md`をcommit・pushした
- [ ] garebare: `isucon-service-name-setup`、ベンチ実行、`isucon-measurement-setup`を済ませた

ここまでが初動。以降は`after-initial.md`の役割分担で進める。
