---
name: bench-log
description: ベンチ後に、ポータルの結果を docs/bench/ に保存し、全サーバーで alp / slow-query を実行して measure-logs/ を取り込み、pushして終わる。「ベンチ終わった」「ベンチ結果はこれ」（ポータルの結果の貼り付け）「alp/slow-queryを出して」「ログを取って」などのリクエストで使用する。ログを出したら完了し、分析・issue起票・PR作成はしない（分析は分析担当が isucon-score-strategy で行う）。
---

# ベンチ結果とログの保存

ベンチを回したブランチをcheckoutした状態で、次をこの順で行う（ファイル名のブランチ・コミットが「そのベンチで動いていたコード」になる）。

```bash
# 1. 貼られた結果を一字も変えずに docs/bench/ へ保存してcommit
mkdir -p tmp
cat > tmp/bench-result.txt <<'BENCH'
<ユーザーが貼った結果をそのまま>
BENCH
make save-bench-log < tmp/bench-result.txt

# 2. 全サーバーで alp / slow-query を実行（measure-logs/ はサーバーからcommit・pushされる）
make remote-measure-all                        # SERVERS="s1 s2" make remote-measure-all で対象を絞れる

# 3. サーバーがpushした measure-logs/ を取り込み、1のcommitをpush
git pull --rebase origin "$(git rev-parse --abbrev-ref HEAD)"
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
```

- 結果が貼られていなければ 1 を飛ばし、2・3 だけ行う
- 3 が終わったら、保存したファイルのパスを返して**完了する**。ログを読んだ分析・改善案・issue起票・PR作成はしない
- SSHがサーバーに届かない環境では 2 を実行できない。ユーザーに手元で `make remote-measure-all` を実行してもらい、完了の返事を待ってから 3 を行う
