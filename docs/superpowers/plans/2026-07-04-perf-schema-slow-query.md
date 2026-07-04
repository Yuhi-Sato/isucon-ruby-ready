# performance_schema スロークエリ集計移行 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make slow-query` を pt-query-digest から performance_schema のダイジェスト集計に置き換え、slow_query_log 常時OFF運用に切り替える。

**Architecture:** `tool-config/slow-query/ranking.sql`（Profile表 + `\G` 詳細ブロックの2部構成）を新規作成し、Makefileの `slow-query` ターゲットを `sudo mysql --table < ranking.sql` に差し替える。統計リセットは `make bench` のMySQL再起動（自動）+ `rm-logs` のTRUNCATE（明示）。my.cnfは当日 `make get-conf` で生成されるため、設定変更はスキル文書の手順として記載する。

**Tech Stack:** GNU Make / MySQL 8 performance_schema / Markdown（スキル文書）

**Spec:** [docs/superpowers/specs/2026-07-04-perf-schema-slow-query-design.md](../specs/2026-07-04-perf-schema-slow-query-design.md)

## Global Constraints

- このリポジトリに自動テストはない。各タスクの検証は `make -n` / grep / （dockerがあれば）MySQL 8コンテナでのSQL実行で行う
- スキル本体は `.agents/skills/` 配下を編集する（`.claude/skills` はシンボリックリンク）
- percona-toolkit のインストール（Makefile `install-tools`）は変更しない（MariaDBフォールバック用に残す）
- `DB_SLOW_LOG` 変数と `rm-logs` の既存truncate行は削除しない
- コミットはConventional Commits形式。1タスク1コミット

---

### Task 1: ranking.sql 作成 + Makefile slow-query 差し替え

**Files:**
- Create: `tool-config/slow-query/ranking.sql`
- Modify: `Makefile:80-82`（`slow-query` ターゲット）

**Interfaces:**
- Produces: `make slow-query`（サーバー上で実行）。出力列 `rank / pct / total_s / calls / avg_ms / max_ms / rows_examined / rows_sent / examined_per_sent / db / query` — Task 3-6 の文書はこの列名を参照する

- [ ] **Step 1: ranking.sql を作成**

`tool-config/slow-query/ranking.sql` を以下の内容で作成する:

```sql
-- make slow-query から実行される（sudo mysql --table < tool-config/slow-query/ranking.sql）
-- ソース: performance_schema.events_statements_summary_by_digest（クエリダイジェスト単位の累積統計）
-- 統計は make bench のMySQL再起動、または make rm-logs のTRUNCATEでリセットされる
-- pct はシステムスキーマ除外後の全クエリ時間に占める割合。TIMER系カラムの単位はピコ秒

SELECT '===== Profile: 合計時間順 上位20（完全なクエリ文は下の詳細ブロック） =====' AS section;

SELECT
  ROW_NUMBER() OVER (ORDER BY SUM_TIMER_WAIT DESC)              AS `rank`,
  ROUND(100 * SUM_TIMER_WAIT / SUM(SUM_TIMER_WAIT) OVER (), 1)  AS pct,
  ROUND(SUM_TIMER_WAIT / 1e12, 2)                               AS total_s,
  COUNT_STAR                                                    AS calls,
  ROUND(AVG_TIMER_WAIT / 1e9, 2)                                AS avg_ms,
  LEFT(DIGEST_TEXT, 60)                                         AS query_head
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME IS NOT NULL
  AND SCHEMA_NAME NOT IN ('mysql', 'sys', 'information_schema', 'performance_schema')
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

SELECT '===== 詳細: 完全なクエリ文とrows examined/sent =====' AS section;

SELECT
  ROW_NUMBER() OVER (ORDER BY SUM_TIMER_WAIT DESC)              AS `rank`,
  ROUND(100 * SUM_TIMER_WAIT / SUM(SUM_TIMER_WAIT) OVER (), 1)  AS pct,
  ROUND(SUM_TIMER_WAIT / 1e12, 2)                               AS total_s,
  COUNT_STAR                                                    AS calls,
  ROUND(AVG_TIMER_WAIT / 1e9, 2)                                AS avg_ms,
  ROUND(MAX_TIMER_WAIT / 1e9, 2)                                AS max_ms,
  SUM_ROWS_EXAMINED                                             AS rows_examined,
  SUM_ROWS_SENT                                                 AS rows_sent,
  ROUND(SUM_ROWS_EXAMINED / GREATEST(SUM_ROWS_SENT, 1), 1)      AS examined_per_sent,
  SCHEMA_NAME                                                   AS db,
  DIGEST_TEXT                                                   AS query
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME IS NOT NULL
  AND SCHEMA_NAME NOT IN ('mysql', 'sys', 'information_schema', 'performance_schema')
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20\G
```

- [ ] **Step 2: Makefile の slow-query ターゲットを差し替え**

`Makefile` の以下の箇所:

```make
.PHONY: slow-query
slow-query: ## slow queryを確認する
	sudo pt-query-digest $(DB_SLOW_LOG)
```

を次に変更する:

```make
.PHONY: slow-query
slow-query: ## performance_schemaのクエリダイジェスト集計を表示する
	sudo mysql --table < tool-config/slow-query/ranking.sql
```

- [ ] **Step 3: make -n で展開コマンドを確認**

Run: `make -n slow-query`
Expected: `sudo mysql --table < tool-config/slow-query/ranking.sql` が表示される（pt-query-digestが消えている）

- [ ] **Step 4: （dockerがあれば）MySQL 8 でSQLを実際に検証**

`docker info` が通る場合のみ実施。通らなければ「サーバー上での初回実行時に確認」とコミットメッセージに残してスキップ:

```bash
docker run -d --name ranking-sql-test -e MYSQL_ALLOW_EMPTY_PASSWORD=1 mysql:8
until docker exec ranking-sql-test mysqladmin ping --silent 2>/dev/null; do sleep 2; done
# 統計を貯めるためアプリ相当のクエリを実行
docker exec ranking-sql-test mysql -e "CREATE DATABASE app; CREATE TABLE app.t (id INT); INSERT INTO app.t VALUES (1),(2),(3); SELECT * FROM app.t; SELECT * FROM app.t WHERE id = 1;"
docker exec -i ranking-sql-test mysql --table < tool-config/slow-query/ranking.sql
docker rm -f ranking-sql-test
```

Expected: Profile表に `app` スキーマのクエリ（INSERT / SELECT）がpct・calls付きで表示され、詳細ブロックに `rows_examined` / `examined_per_sent` が出る。エラーが出た場合はSQLを修正してから再実行する

- [ ] **Step 5: Commit**

```bash
git add tool-config/slow-query/ranking.sql Makefile
git commit -m "feat(slow-query): replace pt-query-digest with performance_schema digest ranking"
```

---

### Task 2: rm-logs にダイジェスト統計のTRUNCATEを追加

**Files:**
- Modify: `Makefile:214-217`（`rm-logs` ターゲット）

**Interfaces:**
- Consumes: なし（Task 1と独立）
- Produces: `make rm-logs` がMySQL稼働中ならダイジェスト統計もリセットする

- [ ] **Step 1: rm-logs にTRUNCATE行を追加**

`Makefile` の以下の箇所:

```make
.PHONY: rm-logs
rm-logs: ## アクセスログ・スロークエリログを空にする
	test ! -f $(NGINX_LOG) || sudo truncate -s 0 $(NGINX_LOG)
	test ! -f $(DB_SLOW_LOG) || sudo truncate -s 0 $(DB_SLOW_LOG)
```

を次に変更する（MySQL停止中でも失敗しないよう `|| true`）:

```make
.PHONY: rm-logs
rm-logs: ## アクセスログ・スロークエリログ・クエリダイジェスト統計を空にする
	test ! -f $(NGINX_LOG) || sudo truncate -s 0 $(NGINX_LOG)
	test ! -f $(DB_SLOW_LOG) || sudo truncate -s 0 $(DB_SLOW_LOG)
	sudo mysql -e "TRUNCATE performance_schema.events_statements_summary_by_digest" 2>/dev/null || true
```

- [ ] **Step 2: make -n で確認**

Run: `make -n rm-logs`
Expected: truncate 2行 + TRUNCATE文の3行が表示される

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat(rm-logs): reset performance_schema digest stats alongside log truncation"
```

---

### Task 3: AGENTS.md / README を更新

**Files:**
- Modify: `AGENTS.md:43`
- Modify: `README.md:245`, `README.md:251` 付近（N+1検出セクション）

**Interfaces:**
- Consumes: Task 1 の出力列名（`calls`）

- [ ] **Step 1: AGENTS.md の make slow-query 行を更新**

変更前:

```
| `make slow-query` | スロークエリログをpt-query-digestで集計する。N+1はCount列で検出する |
```

変更後:

```
| `make slow-query` | performance_schemaのクエリダイジェスト集計を表示する。N+1はcalls列で検出する |
```

（`AGENTS.md:13` の「`pt-query-digest` は導入済み」は事実のまま変更しない）

- [ ] **Step 2: README のN+1検出セクションを更新**

変更前（`README.md:245` 付近の段落末尾）:

```
そのため本リポジトリではN+1検出をgemに頼らず、スロークエリログの集計で代用する。
```

変更後:

```
そのため本リポジトリではN+1検出をgemに頼らず、performance_schemaのクエリダイジェスト集計で代用する。
```

変更前（`README.md:251`）:

```
`pt-query-digest`の出力の `Count` 列（同一クエリパターンの実行回数）を見て、リクエスト数に対して極端に多いクエリがあればN+1を疑う。
```

変更後:

```
`make slow-query` の出力の `calls` 列（同一クエリパターンの実行回数）を見て、リクエスト数に対して極端に多いクエリがあればN+1を疑う。
```

- [ ] **Step 3: 取りこぼしを確認**

Run: `grep -n "pt-query-digest" AGENTS.md README.md`
Expected: `AGENTS.md:13`（導入済みツール一覧）のみヒット。それ以外に残っていれば同様に更新する

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md README.md
git commit -m "docs: update slow-query references to performance_schema digest output"
```

---

### Task 4: isucon-bottleneck-analysis スキルの手順3を書き直す

**Files:**
- Modify: `.agents/skills/isucon-bottleneck-analysis/SKILL.md`

**Interfaces:**
- Consumes: Task 1 の出力列名（`pct` / `calls` / `examined_per_sent`）

- [ ] **Step 1: frontmatter の description を更新**

変更前:

```
description: ISUCONでベンチ実行後に計測結果を解釈し、次の改善対象を1つ決めるときに使う。alp・pt-query-digest・Vernierの出力の読み方、N+1検出を含む。「どこがボトルネック？」「alpの結果を見て」「スロークエリを分析して」「次に何を直す？」などのリクエストで使用する。
```

変更後:

```
description: ISUCONでベンチ実行後に計測結果を解釈し、次の改善対象を1つ決めるときに使う。alp・performance_schema（make slow-query）・Vernierの出力の読み方、N+1検出を含む。「どこがボトルネック？」「alpの結果を見て」「スロークエリを分析して」「次に何を直す？」などのリクエストで使用する。
```

- [ ] **Step 2: 手順3を丸ごと差し替え**

変更前（「## 手順3: pt-query-digestでクエリを特定する」の見出しから `EXPLAIN` コードブロックの手前まで）:

````markdown
## 手順3: pt-query-digestでクエリを特定する

```bash
make slow-query
```

読み方:

- 冒頭の **Profile表**: `Response time %` 降順のランキング。上位から潰す
- 各クエリ詳細の **Count**: 同一パターンの実行回数
- **N+1の検出**: alpの該当エンドポイントのCOUNTに対してクエリCountが数倍以上ならN+1を疑い、一桁以上多ければ（例: リクエスト1,000件に対しクエリ50,000件）ほぼ確実にN+1
- `Rows examined` が `Rows sent` の数十倍以上（各クエリ詳細セクションの1回あたりの値。Profile表のCount×平均ではなく、個々のクエリブロックに出る数値を見る） → インデックス不足。`EXPLAIN` で確認する
````

変更後:

````markdown
## 手順3: performance_schemaでクエリを特定する

```bash
make slow-query   # tool-config/slow-query/ranking.sql を実行（一瞬で終わる）
```

出力は2部構成: **Profile表**（`pct` 降順の横テーブル）と **詳細ブロック**（`\G` 縦形式、完全なクエリ文入り）。

読み方:

- **pct / total_s**: 全クエリ時間に占める割合の降順ランキング。上位から潰す
- **calls**: 同一パターンの実行回数
- **N+1の検出**: alpの該当エンドポイントのCOUNTに対してcallsが数倍以上ならN+1を疑い、一桁以上多ければ（例: リクエスト1,000件に対しクエリ50,000件）ほぼ確実にN+1
- **examined_per_sent**（rows_examined ÷ rows_sent）が数十以上 → インデックス不足。`EXPLAIN` で確認する
- 統計は `make bench` のMySQL再起動でリセットされる累積値。直近ベンチ以降の値であることを確認する（手順「前提の確認」と同じ）
````

- [ ] **Step 3: 「結論の出し方」の例を更新**

変更前:

```
根拠: alp SUM 1位 320s / pt-query-digest Rank 1 (Response time 45%, Count 52,000)
```

変更後:

```
根拠: alp SUM 1位 320s / make slow-query rank 1 (pct 45%, calls 52,000)
```

- [ ] **Step 4: 残存参照を確認**

Run: `grep -n "pt-query-digest\|Response time\|Count" .agents/skills/isucon-bottleneck-analysis/SKILL.md`
Expected: alpのCOUNT列（手順1・N+1検出の文脈）以外にpt-query-digest固有の記述が残っていない

- [ ] **Step 5: Commit**

```bash
git add .agents/skills/isucon-bottleneck-analysis/SKILL.md
git commit -m "docs(skills): rewrite bottleneck-analysis step 3 for performance_schema output"
```

---

### Task 5: isucon-initial-recon スキルに performance_schema 確認手順を追加

**Files:**
- Modify: `.agents/skills/isucon-initial-recon/SKILL.md`（手順4の末尾）

**Interfaces:**
- Consumes: Task 1 の `make slow-query`（フォールバック分岐の説明で参照）

- [ ] **Step 1: 手順4の末尾に計測設定の確認を追加**

手順4「DBスキーマ・データ量を調べる」の「メモする内容: …」の段落の直後に以下を追加する:

````markdown
あわせて計測まわりのDB設定を確認する:

```bash
sudo mysql -e "SELECT @@performance_schema;"   # make slow-query の計測ソース。1ならOK
```

- `0` の場合（MariaDB出題など）: `make get-conf` 後に `sN/etc/mysql/` へ `performance_schema = ON` を追加して反映する。有効化できない場合は従来方式（`long_query_time = 0` でslow logを有効化し `sudo pt-query-digest /var/log/mysql/mysql-slow.log`）にフォールバックする（isucon-server-tuning スキル参照）
- `slow_query_log` は**常時OFF運用**（計測はperformance_schemaで行うためスロークエリログは不要。I/O削減でスコアにも効く）。`make get-conf` 後に `sN/etc/mysql/` へ `slow_query_log = 0` を明示しておく
````

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/isucon-initial-recon/SKILL.md
git commit -m "docs(skills): add performance_schema availability check to initial recon"
```

---

### Task 6: isucon-server-tuning / isucon-final-check を新運用に合わせる

**Files:**
- Modify: `.agents/skills/isucon-server-tuning/SKILL.md:32` と MySQL設定例（`:17-29`）
- Modify: `.agents/skills/isucon-final-check/SKILL.md:28`（手順1）と `:85`（よくある失敗）

**Interfaces:**
- Consumes: Task 1 の `make slow-query` / Task 5 のフォールバック手順

- [ ] **Step 1: server-tuning のスロークエリログ記述を差し替え**

変更前（`isucon-server-tuning/SKILL.md:32`）:

```
- **スロークエリログ（long_query_time=0）は計測時のみ有効。最終ベンチ前に無効化する**（isucon-final-check スキル）
```

変更後:

```
- **スロークエリログは常時OFF（`slow_query_log = 0`）**。クエリ計測はperformance_schema（`make slow-query`）で行うため有効化しない。performance_schemaが使えない場合（MariaDB等）のみ `long_query_time = 0` で一時的に有効化してpt-query-digestで集計し、最終ベンチ前に必ず無効化する（isucon-final-check スキル）
```

- [ ] **Step 2: server-tuning のMySQL設定例に digest_length を追記**

`[mysqld]` 設定例ブロック（`disable-log-bin` の行の後）に以下を追加する:

```ini
# make slow-query（performance_schema集計）で長いクエリが切り詰められる場合に拡大（要再起動）
# max_digest_length = 4096
# performance_schema_max_digest_length = 4096
```

- [ ] **Step 3: final-check 手順1のスロークエリログ項目を差し替え**

変更前（`isucon-final-check/SKILL.md:28`）:

```
- **スロークエリログ無効化**: `sN/etc/mysql/` の `slow_query_log = 0`（または `long_query_time` を大きく戻す）
```

変更後:

```
- **スロークエリログがOFFか確認**: `sN/etc/mysql/` に `slow_query_log = 0`（常時OFF運用のため通常は設定済み。MariaDBフォールバック等で有効化した場合はここで必ず戻す）
- **（任意）performance_schema無効化**: `sN/etc/mysql/` に `performance_schema = OFF`（数%のオーバーヘッド削減。以後 `make slow-query` での計測は不能になるため、最終ベンチ直前の絞り出しとしてのみ検討）
```

- [ ] **Step 4: final-check よくある失敗の1行目を更新**

変更前（`isucon-final-check/SKILL.md:85`）:

```
| slow_query_log を付けたまま提出し、無駄なI/Oでスコアを落とす | 手順1を60分前に必ず実施 |
```

変更後:

```
| フォールバックで有効化したslow_query_logを戻し忘れ、無駄なI/Oでスコアを落とす | 手順1を60分前に必ず実施 |
```

- [ ] **Step 5: リポジトリ全体で最終確認**

Run: `grep -rn "pt-query-digest\|long_query_time" Makefile AGENTS.md README.md .agents/skills/`
Expected: 残るのは (1) AGENTS.md:13 の導入済みツール一覧、(2) initial-recon / server-tuning / final-check のMariaDBフォールバック文脈のみ

- [ ] **Step 6: Commit & push**

```bash
git add .agents/skills/isucon-server-tuning/SKILL.md .agents/skills/isucon-final-check/SKILL.md
git commit -m "docs(skills): switch server-tuning and final-check to slow-log-off operation"
git push
```
