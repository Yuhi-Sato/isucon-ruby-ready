---
name: isucon-bench-result
description: ISUCONでベンチマークが終わった直後に、ユーザーの合図（「ベンチ終わった」「ベンチ結果はこれ」＋ポータルの結果の貼り付け）を受けて、(1) ベンチ結果を docs/bench/ に保存してcommit、(2) alp / slow-query の集計をDiscordに通知して measure-logs をcommit・push、(3) isucon-score-strategy で次の一手を決める、の3つを一続きで行う。「ベンチ終了」「ベンチ回した」「結果を記録して」「/isucon-bench-result」などのリクエストで使用する。ベンチの実行そのもの・デプロイ・コード変更は行わない。
---

# ベンチ終了後の記録・通知・分析（ベンチ1回につき1回実行）

ベンチが終わったら、記録（bench log）→ 計測の通知（alp / slow-query → Discord）→ 分析（スコアストラテジー）を**この順で全部**やる。1つでも飛ばすと「どの変更で上がった/下がったか」が後で追えなくなる。

ベンチの終了は hook では検知できない（ポータルのボタンで実行し、結果もポータルにしか出ない）ので、**ユーザーが「ベンチ終わった」と合図し、ポータルの結果を貼る**のを起点にする。合図だけで結果が貼られていない場合は、手順1の前に貼ってもらう（貼られるまで手順2以降に進んでよいが、手順3は結果なしでは進めない）。

## 前提の確認

最初に次を確認し、ズレていたら先に直す（直せなければユーザーに伝えて止まる）。

```bash
git rev-parse --abbrev-ref HEAD   # ベンチを回したブランチと一致しているか
git status --short                 # 未コミットの変更が残っていないか（残っていればログのcommitに巻き込まない）
```

- ベンチログのファイル名にはブランチとコミットが入るので、**ベンチで動いていたブランチ・コミットをcheckoutした状態**で保存する。違うブランチにいるなら `git checkout <ベンチしたブランチ>` してから進む
- ユーザーが「どのブランチでベンチしたか」を言っていないときは、直前に `make remote-bench-prep-*` / `make remote-deploy-*` を実行したブランチ（会話中に無ければユーザーに聞く）を使う

## 手順1: ベンチ結果を docs/bench/ に保存してcommit

ユーザーが貼ったポータルの結果を**一字も変えずに**一時ファイルへ書き、`make save-bench-log` に流す。

```bash
mkdir -p tmp
cat > tmp/bench-result.txt <<'BENCH'
<ユーザーが貼った結果をそのまま>
BENCH
make save-bench-log < tmp/bench-result.txt   # saved: docs/bench/<日時>-<ブランチ>-<コミット>.md と出る
git add docs/bench && git commit -m "ベンチ結果を記録: <スコア> (<pass/fail>)" -- docs/bench
```

- 保存先のファイル名（`saved:` の行）を控えておく。手順3の分析対象になる
- スコアの数値と pass/fail をコミットメッセージに入れる（`git log` だけで推移を追えるようにするため）
- push は手順2の後にまとめて行う（サーバーからの measure-logs のpushと衝突しないよう、先に pull --rebase する）

## 手順2: alp / slow-query をDiscordに通知し、measure-logs を取り込む

計測ログはサーバー上で集計してDiscordに送り、同時にサーバーからcommit・pushされる（`scripts/push-measure-log.sh`）。ローカルからは `make remote-nd-all` で全サーバーへ並列に流せる。

まず、この環境からサーバーへSSHできるかを確認する。

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 s1 true && echo ssh-ok || echo ssh-ng
```

- `ssh-ok` なら実行する。DB分離などで対象を絞る場合は `SERVERS` で指定する

  ```bash
  make remote-nd-all                 # 全サーバー（s1 s2 s3）
  SERVERS="s1 s2" make remote-nd-all # 対象を絞る
  ```

- `ssh-ng`（Claude Code on the web など、`~/.ssh/config` の s1/s2/s3 に届かない環境）なら、**ユーザーに手元で次を実行してもらい、完了の返事を待つ**。代わりの手段（サーバーの再現・推測での集計）は取らない

  ```bash
  make remote-nd-all
  ```

通知が終わったら、サーバーがpushした measure-logs と手順1のcommitを揃える。

```bash
git pull --rebase origin "$(git rev-parse --abbrev-ref HEAD)"
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
ls -t measure-logs/alp | head -3 ; ls -t measure-logs/slow-query | head -3   # 今回のログが来ているか
```

`make remote-nd-all` が失敗したサーバーがあれば（Webhook未設定・SSH不通など）、どのサーバーで何が失敗したかをそのまま伝える。通知に失敗しても集計ログ自体は `measure-logs/` に保存・commitされているので、手順3には進める。

## 手順3: スコアストラテジーで次の一手を決める

`isucon-score-strategy` スキルを起動し、手順1で保存したベンチログを分析対象として渡す。手順0（マニュアル・スコアモデル・ログの保存）のうち保存は済んでいるので、手順2（ログの分類）から進める。

- `docs/manual.md` / `docs/score-model.md` が無ければ、スキルの指示どおり先に揃える（マニュアル無しでは提案しない）
- 前回のベンチログ（`docs/bench/` の1つ前）との比較表を必ず作る
- 分析結果は `docs/strategy/<ベンチログと同じファイル名>.md` に保存してcommit・pushする

alp / slow-query の中身は**このスキルでは読まない**（スコアストラテジーは「何が点になるか」、alp / slow-query は「なぜ遅いか」で別作業）。ストラテジーで「規則上の未達なし。計測に進む」と結論した場合にだけ、次の作業として `measure-logs/` の最新ログを読むことを提案する。

## 最後に報告すること

1つのメッセージで次をまとめる。

- 保存したベンチログのパスとスコア（前回 → 今回）
- Discord通知の結果（成功したサーバー / 失敗したサーバーと理由）
- ストラテジーの推奨案（1案）と、次のベンチで確認する行
- 次の作業（実装に進むか、計測ログを読むか）

## やらないこと

- ベンチの実行、デプロイ（`make remote-bench-prep-*` / `remote-deploy-*`）、コードや設定の変更
- ポータルの結果を要約・整形して保存すること（原文のまま保存する。分析は手順3で別に書く）
- SSHが通らない環境で `make remote-nd-all` の代替を勝手にやること（ユーザーに実行を頼む）

## よくある失敗

| 失敗 | 対策 |
|---|---|
| 別のブランチにいる状態で保存し、ファイル名のブランチ・コミットが実際にベンチしたコードと食い違う | 「前提の確認」でブランチを合わせてから `make save-bench-log` する |
| 結果を貼ってもらう前にストラテジーを始めて、推測で提案する | 手順3は貼られた結果の保存後にだけ進める |
| `make remote-nd-all` を飛ばして alp / slow-query が残らない | 手順2はSSH不通でもユーザーに実行を頼み、完了を待ってから進む |
| ローカルのpushがサーバーからの measure-logs のpushに拒否される | 手順2の `git pull --rebase` を先に行う |
| 分析を会話にだけ残す | 手順3で `docs/strategy/` に保存してcommit・pushする |
