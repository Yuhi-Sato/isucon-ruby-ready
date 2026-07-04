# pt-query-digest → performance_schema 置き換え設計

日付: 2026-07-04
ステータス: 承認済み（実装プラン未作成）

## 背景・目的

`make slow-query`（`sudo pt-query-digest $(DB_SLOW_LOG)`）はスロークエリログ全体をパースするため、
ログが育つと集計に時間がかかりサーバーCPUも食う。MySQLの
`performance_schema.events_statements_summary_by_digest` はダイジェスト単位で集計済みのため、
SQLを1発投げるだけで同等の情報（時間ランキング・実行回数・rows examined/sent）が一瞬で取れる。

方針: **完全置き換え + slow_query_log 常時OFF**。スロークエリログのディスクI/Oが消えるため、
計測がベンチスコアに与える影響も減る。

## 1. `make slow-query` の差し替え

Makefile:

```make
.PHONY: slow-query
slow-query: ## performance_schemaのクエリダイジェスト集計を表示する
	sudo mysql --table < tool-config/slow-query/ranking.sql
```

`tool-config/slow-query/ranking.sql` を新規作成。pt-query-digestと同じ読み方ができる2部構成:

1. **Profile表**（横テーブル）: rank / 全体に占める時間% / 合計時間(s) / calls / avg_ms /
   クエリ先頭60文字。`SUM_TIMER_WAIT` 降順・上位20件
2. **詳細ブロック**（`\G` 縦形式）: 完全な `DIGEST_TEXT`、rows_examined / rows_sent とその比率
   （インデックス不足検出用）、max_time

共通条件: システムスキーマ（`mysql` / `sys` / `information_schema` / `performance_schema`）を除外。

`make ns`（Slack通知）はターゲット名がそのままなので変更不要。

## 2. 統計のリセット

- performance_schemaはメモリ上の統計のため、`make bench` に含まれるMySQL再起動で自動リセットされる
  （現行の「ベンチ前にログが消える」挙動と同等）
- 加えて `rm-logs` に `TRUNCATE performance_schema.events_statements_summary_by_digest` を追加
  （MySQL停止中は `|| true` で無視）。再起動を伴わないリセットにも対応する

## 3. my.cnf の当日設定（ドキュメント化のみ）

`sN/etc/mysql/` は当日 `make get-conf` で生成されるため、リポジトリで事前変更はできない。
スキルに手順として記載する:

- `slow_query_log = 0` を明示（従来の `long_query_time = 0` 設定手順は削除）
- `performance_schema = ON` はMySQL 8ではデフォルト。初動調査で `SELECT @@performance_schema` を確認
- **MariaDB出題の場合はperformance_schemaがデフォルトOFF**。my.cnfで有効化するか、
  従来のslow log + pt-query-digestにフォールバック（percona-toolkitは残置）
- 任意: `max_digest_length` / `performance_schema_max_digest_length = 4096`
  （長いクエリの切り詰め回避。要再起動）

## 4. ドキュメント・スキル更新

| ファイル | 変更 |
|---|---|
| AGENTS.md | `make slow-query` の説明文を更新 |
| isucon-bottleneck-analysis | 手順3を新出力の列名（pct / calls / rows_examined比）で書き直し。N+1検出ロジック（calls対リクエスト数比）は同じ |
| isucon-initial-recon | performance_schema有効確認 + my.cnf設定手順を追加 |
| isucon-server-tuning | 「long_query_time=0は計測時のみ」の記述を「slow logは常時OFF、計測はperformance_schema」に変更 |
| isucon-final-check | 手順1のスロークエリログ無効化を「設定済みであることの確認のみ」に変更。任意の絞り出しとして `performance_schema = OFF`（数%のオーバーヘッド削減、ただし以後計測不能）を追記 |
| README | N+1検出セクション（pt-query-digestのCount列の記述）をperformance_schemaのcalls列に更新 |

## 5. 変えないもの

- `install-tools` のpercona-toolkit（MariaDBフォールバック用に残す）
- `DB_SLOW_LOG` 変数と `rm-logs` のtruncate（slow logが存在すれば消すだけなので無害）
- alp / Vernier / nginx まわり一式

## 検討して却下した案

- **sys.statement_analysis の利用**: 自作SQL不要だが、列構成が固定でクエリ文が切り詰められ、
  pt-query-digest相当の読み方（Profile表→詳細）ができない
- **併存（make ps-query 追加）**: ターゲットが増えて `make ns` の通知先選択も複雑になる。
  slow log OFFにする以上、pt-query-digest側は実質使えないため併存の意味が薄い
- **slow log 温存**: I/O削減のスコア寄与を捨てることになる。フォールバックが必要なのは
  MariaDB出題時のみで、その場合は当日my.cnfで有効化すれば足りる
