---
name: isucon-remote-setup
description: ISUCONの初動で、各競技サーバー（s1/s2/s3）の初回セットアップ（READMEの「3. セットアップする」＝git init→origin/main取得→make setup-sN）をサーバーにログインせずローカルからSSHで流すときに使う。「初動のセットアップをして」「make setup-s1を実行して」「サーバーをセットアップして」「setup-sNをローカルから流して」などのリクエストで使用する。サービス名の設定（isucon-service-name-setup）や計測設定（isucon-measurement-setup）はこの後に行う別作業。
---

# 初回セットアップ（make setup-sN）をローカルから流す

READMEの「3. セットアップする」をサーバーごとにSSH越しで実行する。`make setup-sN` は最後に `git push origin main` するため、**s1 → s2 → s3 の順に1台ずつ**流す。並列にすると後続のpushがnon-fast-forwardで拒否される（`setup.sh` は pull し直さない）。

前提: `~/.ssh/config` に `Host s1/s2/s3`（`ForwardAgent yes`）があり、ローカルの ssh-agent にGitHub用の鍵が載っていること（README「2. SSHを設定する」）。配布ルートは `/home/isucon`（違えば `REMOTE_DEPLOY_PATH` の値に読み替える）。

## 手順

1. 事前確認（読み取りのみ）。どれかが通らなければ止めてユーザーに伝える

   ```bash
   REPO=$(git remote get-url origin)   # git@github.com:... のSSH形式であること（https なら止める）
   git fetch origin main
   git ls-tree --name-only origin/main | grep -E '^s[1-3]$'   # 出てきたサーバーはセットアップ済み
   ssh s1 'ssh -T git@github.com 2>&1; cd /home/isucon && ls && git status --short 2>&1 | head'
   ```

   - `ssh -T` の出力に `successfully authenticated` が無い → agent forwarding が効いていない。ローカルで `ssh-add -l` を確認させる
   - `origin/main` に `sN/` が既にある → そのサーバーはセットアップ済み。再実行すると `git commit` が「nothing to commit」で失敗する／`checkout -f` でサーバー上の変更が消えるので、**実行せずユーザーに確認する**

2. 1台ずつ実行する（s1 が成功してから s2、s2 が成功してから s3）。`install-tools.sh` で数分かかるので Bash の timeout は 600000 にする

   ```bash
   N=s1
   ssh "$N" "cd /home/isucon && git init -b main && { git remote add origin '$REPO' 2>/dev/null || git remote set-url origin '$REPO'; } && git fetch origin main && git checkout -f -B main origin/main && make setup-$N"
   ```

   失敗したら次のサーバーへ進まず、出力を見て原因を報告する。

3. 結果を確認し、ローカルのmainに取り込む

   ```bash
   git fetch origin main && git log --oneline -5 origin/main   # chore: setup (s1)〜(s3) が並ぶ
   ```

   ローカルで main をcheckoutしていれば `git pull`、作業ブランチにいるならそのまま（次にブランチを切るときに origin/main から切る）。

## よくある失敗

| 症状 | 原因・対処 |
|------|-----------|
| `Permission denied (publickey)`（GitHub） | agent forwarding 不成立。ローカルの `ssh-add -l` が空、または `ForwardAgent yes` が無い |
| s2 の `git push` が `rejected (fetch first)` | 並列実行した／s1 の完了前に s2 を始めた。s2 で `git pull --rebase origin main && git push origin main` してから s3 へ |
| `nothing to commit` で終了 | そのサーバーはセットアップ済み（手順1で検出できる） |
| `make: *** No rule to make target 'setup-s1'` | `checkout` 前に失敗している、または配布ルートが `/home/isucon` ではない |
