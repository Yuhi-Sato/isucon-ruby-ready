# remote-setup.sh分離とセットアップ再開性の設計

日付: 2026-08-07
ステータス: 承認済み

## 背景・課題

`setup.sh`のサーバー側処理（tarball展開〜git配線）は`setup.sh`内のヒアドキュメント（`REMOTE_SCRIPT`）に埋め込まれており、SSH接続ユーザーの権限・`$HOME`で実行される。このため以下の問題がある。

1. **SSHユーザーが`isucon`でない環境（練習用EC2等、`ubuntu`等の管理ユーザーで接続する構成）では`/home/isucon`への`tar`展開が権限エラーで失敗し、そこで詰む。**
   本番競技では`isucon`で直接SSHできる想定だが、練習環境ではこのケースが実際に発生した。
2. 失敗後にサーバー上で`sudo -i -u isucon`して手動で`curl | tar`を実行しても、その先（`server-setup.sh`・git init・Deploy key配線・push）はスクリプト化されておらず（READMEの手動フォールバックは`server-setup.sh`まで）、手作業での再現が難しい。
3. Deploy keyはSSH接続ユーザーの`$HOME/.ssh`に生成されるため、接続ユーザーが`ubuntu`だと鍵が`ubuntu`のhomeに作られ、`isucon`側でのgit操作と噛み合わない。

## 設計方針

4点セットで対応する。

### 1. サーバー側処理を`remote-setup.sh`に分離

`setup.sh`の`REMOTE_SCRIPT`ヒアドキュメント（GitHub認証疎通確認〜tarball展開〜`server-setup.sh`〜git配線）を、リポジトリ直下の新規ファイル`remote-setup.sh`に切り出す。

- `setup.sh`からは`ssh ... bash -s -- <args> < remote-setup.sh`で流し込む（通常フローの挙動は変えない）
- インターフェース: `remote-setup.sh <s1|s2|s3> <repo-name> [--dir <path>]`
  - `REPO_OWNER`（`Yuhi-Sato`固定）・SSH URL・鍵ファイル名（`github_deploy_<repo-name>`）は`repo-name`からスクリプト内で導出する。単体実行時に人間が渡す引数を最小にするため、導出ロジックは`setup.sh`と重複して持つ（安定した3行程度であり許容）
- `sh`（dash）互換は要求しない。`setup.sh`同様bash前提とし、shebangは`#!/bin/bash`、実行方法は`bash remote-setup.sh ...`または`bash -s`経由

### 2. `remote-setup.sh`は単体実行可能・冪等にする

サーバー上で`sudo -i -u isucon`した状態から、これ1本でtarball展開以降を再開できる。

```bash
# 公開リポジトリなのでraw URLで取得して実行できる（tar展開前でも入手可能）
curl -fsSL https://raw.githubusercontent.com/Yuhi-Sato/isucon-ruby-ready/main/remote-setup.sh \
  | bash -s -- s1 <repo-name>
```

- **Deploy keyの自己修復**: 実行ユーザーの`$HOME/.ssh/github_deploy_<repo-name>`が無ければ生成する（`setup.sh`の失敗後は鍵が`ubuntu`側にしか無いケースがあるため）。GitHub認証疎通確認に失敗した場合は、公開鍵と「ローカルで実行すべき正確な`gh repo deploy-key add`コマンド」を表示して終了する。鍵登録後の再実行で続きから進む
- **冪等性**: tar展開は上書きで冪等、`server-setup.sh`は既存の冪等ガードを持つ、git配線（init / remote設定 / core.sshCommand / commit / push）は既存のガード付きロジックをそのまま移設する。何度実行しても安全
- 既知の限界（自動修復しない）: 過去の失敗実行で`TARGET_DIR`に他ユーザー所有のファイルが残っている場合、`isucon`での上書き展開が失敗しうる。その場合は`chown`での手動修復を案内するのみとする

### 3. `setup.sh`に自動sudoフォールバック

サーバー側処理（Deploy key生成・`remote-setup.sh`実行）の前に`ssh <server> whoami`で接続ユーザーを確認し、`isucon`でなければ両フェーズを`sudo -iu isucon bash -s`でラップして実行する。

- `sudo -i`により`$HOME`・カレントが`isucon`のものになるため、鍵は必ず`isucon`のhomeに作られる
- 練習環境の管理ユーザーはpasswordless sudoを持つ前提（ISUCON系環境の標準構成）。sudoにパスワードが必要な環境ではエラーになるが、その場合は手動フォールバック（設計2）に誘導する
- 本番の`isucon`直接続では従来どおりsudoなしで実行される

### 4. READMEのフォールバック節を更新

「ローカル経由が使えない場合のフォールバック」節を、`remote-setup.sh`ワンライナー（上記raw URL方式）による再開手順に書き換える。git配線まで含めてカバーされること、鍵未登録時は表示される`gh`コマンドをローカルで実行してから再実行することを明記する。あわせてsetup.sh本体の説明に自動sudoの挙動を1行追記する。

## データフロー（変更後）

```
setup.sh（ローカル）
  ├─ gh auth確認 / リポジトリ作成・存在確認（変更なし）
  ├─ ssh <server> whoami → isuconでなければ以降を sudo -iu isucon でラップ
  ├─ [SSH 1] Deploy key生成（ヒアドキュメント、既存ロジック）→ pubkey回収 → gh deploy-key add（変更なし）
  └─ [SSH 2] bash -s -- <role> <repo-name> [--dir ...] < remote-setup.sh
       └─ remote-setup.sh: known_hosts → 認証疎通（失敗時は登録手順を表示して終了）
          → (s1) tar展開 → server-setup.sh → git init/remote/core.sshCommand/commit/push
          → (s2/s3) git init/remote/core.sshCommand → fetch/checkout → server-setup.sh
```

## エラーハンドリング

- `remote-setup.sh`は`set -euo pipefail`。認証疎通失敗時のみ、復旧手順（pubkey表示＋`gh`コマンド）を出して明示的に終了する
- `setup.sh`の`whoami`確認が失敗した場合（SSH不通）は従来どおりそのままエラー終了
- 引数バリデーション（role形式・repo-name必須）は`remote-setup.sh`側でも行う（単体実行があるため）

## テスト・検証

- `bash -n`と`shellcheck`（利用可能なら）を`setup.sh`・`remote-setup.sh`に通す
- 実環境検証は練習用EC2で実施する（本設計のスコープ外の手動作業）:
  1. `isucon`直接続でのsetup.sh通し実行（従来フロー回帰）
  2. `ubuntu`接続での自動sudo経由の通し実行
  3. サーバー上`sudo -i -u isucon`からの`remote-setup.sh`単体実行（鍵なし状態→案内表示→登録→再実行）

## スコープ外

- `server-setup.sh`の変更（既存のまま）
- 失敗実行が残した他ユーザー所有ファイルの自動修復
- CI（deploy.sh等）への変更
