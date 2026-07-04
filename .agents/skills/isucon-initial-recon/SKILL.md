---
name: isucon-initial-recon
description: ISUCON競技開始直後の初動調査で使う。レギュレーション確認、問題アプリの構造把握、DBスキーマ・インデックス調査、Makefile変数・alp設定の問題適応、ベースラインスコア記録まで。「初動調査して」「問題を把握して」「まず何をすればいい？」などのリクエストで使用する。
---

# ISUCON 初動調査

## 概要

競技開始から最初のベンチまでに「どこで点が入り、どこが遅そうか」の地図を作る。
ここで作った地図が以降の全改善の土台になる。**改善はまだしない。調査に徹する。**

## チェックリスト

上から順に実施し、結果を `docs/recon.md` にメモとして残す（チーム全員とエージェントが参照する）。

### 1. レギュレーション・当日マニュアルを読む（最優先）

以下を必ず抜き出してメモする:

- **スコア計算式**（成功リクエストの重み、減点条件）
- **失格条件**（レスポンス内容の変更禁止範囲、DNS/IP制約など）
- **再起動試験の有無**（あるなら isucon-final-check スキルで再起動試験が必須になる）
- ベンチマークの整合性チェック内容（キャッシュ可能性の判断材料になる）

### 2. リポジトリ・Makefile変数を問題に合わせる

```bash
# Makefile冒頭の変数を確認・修正（AGENTS.mdの前提）
# SERVICE_NAME / APP_DIR / DB_SERVICE_NAME
systemctl list-units --type=service | grep -iE 'isu|ruby|mysql|maria|nginx'
```

READMEの「当日チェックリスト」（alp設定・nginx ltsvフォーマット・Slack Webhook）も済んでいるか確認する。

### 3. アプリ構造を把握する

```bash
# ルート一覧（Sinatra想定）
grep -nE "^\s*(get|post|put|delete|patch) " webapp/ruby/*.rb

# SQLを queries/ 以下に抽出
make extract-sql
```

- エンドポイントごとに「何をするか」を1行でメモする
- 初期化エンドポイント（`POST /initialize` 等）の中身を読む。**DBを再構築する場合、後で追加するインデックスはここに仕込む必要がある**（isucon-optimization-patterns スキル参照）

### 4. DBスキーマ・データ量を調べる

```bash
sudo mysql -e "SHOW DATABASES;"
sudo mysql <db> -e "SHOW TABLES;"
sudo mysql <db> -e "SHOW CREATE TABLE <table>\G"   # インデックス有無を確認
sudo mysql <db> -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = '<db>' ORDER BY table_rows DESC;"
```

メモする内容: テーブル一覧・行数・**インデックスが無いテーブル**・BLOB/TEXTカラム（画像がDBに入っていれば静的配信化の候補）。

あわせて計測まわりのDB設定を確認する:

```bash
sudo mysql -e "SELECT @@performance_schema;"   # make slow-query の計測ソース。1ならOK
```

- `0` の場合（MariaDB出題など）: `make get-conf` 後に `sN/etc/mysql/` へ `performance_schema = ON` を追加して反映する。有効化できない場合は従来方式（`long_query_time = 0` でslow logを有効化し `sudo pt-query-digest /var/log/mysql/mysql-slow.log`）にフォールバックする（isucon-mysql-tuning スキル参照）
- `slow_query_log` は**常時OFF運用**（計測はperformance_schemaで行うためスロークエリログは不要。I/O削減でスコアにも効く）。`make get-conf` 後に `sN/etc/mysql/` へ `slow_query_log = 0` を明示しておく

### 5. alpのmatching_groupsを合わせる

手順3のルート一覧をもとに `tool-config/alp/config.yml` の `matching_groups` を編集する。
可変部分（`:id` 等）を正規表現でまとめないと、alpの集計がURLごとにバラけて使いものにならない。
編集はローカル→push→サーバーで `git pull` の流れ（サーバーのワーキングツリーは直接編集しない）。

### 6. ベースラインを記録する

```bash
make bench          # サーバー上で実行するベンチの「準備」（ログ消去・設定反映・全再起動）
# → ベンチマーカー本体はポータル等から実行し、初回スコアを docs/recon.md に記録
make alp            # ベンチ後すぐ集計
make slow-query
```

初回の `make alp` / `make slow-query` の上位結果もメモに貼る。これが最初の改善対象になる（解釈は isucon-bottleneck-analysis スキル）。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| レギュレーションを読まずに改善を始め、失格条件を踏む | 手順1を必ず最初に行う |
| `SERVICE_NAME` が違うまま `make bench` して古いアプリを計測する | 手順2で `systemctl` の実サービス名を確認する |
| matching_groups未設定でalpの結果がURLごとに分散する | 手順5をベンチ前に済ませる |
| 調査中に「ついでに」コードを直し始める | 初動では改善しない。改善は計測結果を見てから |
