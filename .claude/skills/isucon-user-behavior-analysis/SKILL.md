---
name: isucon-user-behavior-analysis
description: ISUCONでユーザー行動履歴（ユーザーID付きアクセスログ）の記録を仕込み、DuckDBで分析するときに使う。導入（Rackミドルウェア＋nginx設定）と分析（行動フロー・リピート検出・ユーザー負荷分布、アドホックSQL）の両方をまとめる。「行動履歴を分析して」「ユーザーの動きを追って」「DuckDBで集計して」「キャッシュできる場所をユーザー軸で探して」などのリクエストで使用する。
---

# ユーザー行動履歴の記録とDuckDB分析

## 概要

alpの集計はエンドポイント軸の横断集計であり、**ユーザー軸の時系列（行動フロー）は扱えない**。このスキルはそのギャップを埋める：Rackミドルウェアでレスポンスに`X-User-Id`ヘッダーを付け、nginxがLTSVの`userid`フィールドに記録し、DuckDBでユーザー単位の行動を分析する（用語の定義は[CONTEXT.md](../../../CONTEXT.md)「ユーザー行動履歴」参照）。

設計上の性質：

- **ログは常に最新ベンチ1回分**（`make bench`がtruncateする）。蓄積・スナップショットはしない。分析はベンチ直後に行う
- **DuckDBは毎回生ログを直読みする**（事前ロードなし）。ISUCON規模のログ（〜数百MB）なら秒単位で読める
- DuckDB CLI・nginxの`userid`フィールドはセットアップ時点で導入済み。**当日やるのはミドルウェアの挿入だけ**

初動調査（isucon-initial-recon スキル）の一部として導入し、以降すべてのベンチで行動履歴が自動的に手に入る状態にする。

## 1. 当日の導入手順（初動調査で実施）

### 1-1. セッションのユーザーIDキーを確認する

```bash
# セッションへの書き込み箇所を探す（Sinatra想定）
grep -nE "session\[" webapp/ruby/*.rb | grep -vE "^\s*#"
```

`session[:user_id] = ...` のような代入行から、ユーザーIDが入るキー名を特定する。
セッションに直接IDがなくトークン等の場合は、そのトークンをそのままIDとして使ってよい（ユーザーの区別さえつけば分析には十分）。

### 1-2. ミドルウェアを挿入する

**ローカルで編集→push→デプロイ**（サーバーのワーキングツリーは直接編集しない）。

1. このスキルと同じディレクトリの [user_id_logger.rb](user_id_logger.rb) を `webapp/ruby/` にコピーする
2. `SESSION_KEY` を手順1-1で確認したキー名に書き換える
3. `config.ru` に追加する:

```ruby
require_relative "user_id_logger"
use UserIdLogger
```

挿入位置はレスポンス経路でセッションを読む実装のため、セッションミドルウェアの内外どちらでも動く。

### 1-3. nginxに`proxy_hide_header`を設定する

`make get-conf` 済みの `sN/etc/nginx/` 配下で、アプリへproxyしているlocationに追加する：

```nginx
proxy_hide_header X-User-Id;
```

これで**ログには残り、ベンチマーカーへのレスポンスからは消える**（`$upstream_http_x_user_id`変数はヘッダーを隠しても値を保持する）。LTSVの`userid`フィールド自体は [ltsv-log-format.conf](../../../tool-config/nginx/ltsv-log-format.conf) で定義済み。

### 1-4. 動作確認

デプロイ後、ログインを伴うリクエストを1回流してからログ末尾を見る：

```bash
ssh s1 'sudo tail -3 /var/log/nginx/access.log | grep -oE "userid:[^\t]*"'
```

- ログイン後のリクエストで `userid:<ID>` が出ればOK
- 全部 `userid:-` の場合: `SESSION_KEY`の間違い、またはセッションが`env["rack.session"]`以外の仕組み（自前トークン等）
- `userid:` フィールド自体が無い場合: nginxのltsv設定が古い（`make deploy-conf`→nginx再起動を確認）
- ベンチマーカーのレスポンス検証に引っかからないか、この時点で一度ベンチを回して確認する

## 2. 定型レシピ（ベンチ後にまず眺める）

サーバー上で実行する（エージェントはSSH経由: `ssh s1 "cd /home/isucon && make duckdb-flow"`）。

| コマンド | 見えるもの | 次のアクション |
|---|---|---|
| `make duckdb-flow` | 「URI→次のURI」の遷移集計。支配的な行動フローと、フロー中の遅い区間（`to_avg_reqtime`） | 遷移元のレスポンスに次のリクエストで使うデータを埋め込めないか、遅い遷移先を優先改善できないか |
| `make duckdb-repeat` | 同一ユーザー×同一URIの繰り返しGET。`repeat_reqtime_sum`が潰せる時間の総量 | 上位をキャッシュ候補に（isucon-nginx-caching / isucon-optimization-patterns スキル） |
| `make duckdb-heavy-users` | ユーザーごとのリクエスト数・総reqtime | 重いユーザーのuseridを控え、セクション3のアドホックSQLで行動を時系列に追う |

読み方の注意：

- nginxの`time`は**1秒精度のリクエスト完了時刻**。VIEWは`start_ts`（完了時刻−reqtime）で並べるが、同一秒内の順序は近似。集計ベースの遷移分析には十分、厳密な1リクエスト単位の因果には使わない
- `userid`がNULLの行＝未ログインリクエストと静的ファイル。レシピは除外済み
- `uri_norm`は数値セグメントのみ`:id`に正規化する。**UUID等が出る問題では当日 `tool-config/duckdb/init.sql` の`uri_norm`に正規化を追記する**（alpのmatching_groups調整と同じ趣旨・同じタイミング）

## 3. アドホック分析

`access_log` VIEW（[init.sql](../../../tool-config/duckdb/init.sql)で定義）のスキーマ：

| カラム | 型 | 内容 |
|---|---|---|
| `ts` / `start_ts` | TIMESTAMPTZ | リクエスト完了時刻（1秒精度）／開始時刻（近似） |
| `userid` | VARCHAR | ユーザーID。未ログイン・静的ファイルはNULL |
| `uri` / `uri_norm` | VARCHAR | 生URI（クエリ文字列含む）／正規化済みパス |
| `method` / `status` | VARCHAR / INT | |
| `reqtime` / `apptime` | DOUBLE | nginx計測／upstream計測（秒） |
| `size` / `host` / `cache` | | body bytes / remote_addr / X-Cacheヘッダー |

実行パターン（init.sqlを前置してヒアドキュメントで流す）：

```bash
ssh s1 'cd /home/isucon && { cat tool-config/duckdb/init.sql; cat <<"SQL"
-- 例: 特定ユーザーの行動を時系列で追う（heavy-usersで見つけたIDを入れる）
SELECT ts, method, uri, status, reqtime FROM access_log
WHERE userid = ''101'' ORDER BY start_ts, ts LIMIT 50;
SQL
} | sudo duckdb'
```

よく使う切り口の例：

```sql
-- 遅いリクエストの直前に同一ユーザーが何をしていたか（書き込み→直後の読み込みの因果を探す）
WITH seq AS (
  SELECT userid, uri_norm, reqtime,
         lag(uri_norm) OVER (PARTITION BY userid ORDER BY start_ts, ts) AS prev_uri,
         lag(method)   OVER (PARTITION BY userid ORDER BY start_ts, ts) AS prev_method
  FROM access_log WHERE userid IS NOT NULL
)
SELECT prev_method, prev_uri, count(*) AS cnt, round(avg(reqtime), 3) AS avg_reqtime
FROM seq
WHERE uri_norm = '/items/:id'          -- alpで特定した遅いエンドポイントを入れる
GROUP BY 1, 2 ORDER BY cnt DESC LIMIT 20;

-- ユーザーの最初のNリクエスト（シナリオの導入部の推定）
SELECT rn, uri_norm, count(*) AS cnt FROM (
  SELECT uri_norm, row_number() OVER (PARTITION BY userid ORDER BY start_ts, ts) AS rn
  FROM access_log WHERE userid IS NOT NULL
) WHERE rn <= 5 GROUP BY 1, 2 ORDER BY rn, cnt DESC;
```

## よくある失敗

| 失敗 | 対策 |
|---|---|
| ミドルウェアを入れる前のベンチのログに行動分析をかけて全行NULL | 導入は初動調査で済ませる。`userid`の有無は手順1-4で確認 |
| `X-User-Id`がベンチマーカーに漏れてレスポンス検証で減点/FAIL | `proxy_hide_header X-User-Id;` を必ずセットで入れる（手順1-3） |
| `uri_norm`が正規化されず遷移集計がURLごとにバラける | alpのmatching_groups調整と同時に`init.sql`の`uri_norm`も問題に合わせる |
| ログのフィールド順とVIEW定義がずれて列が壊れる | `ltsv-log-format.conf`を変えたら`init.sql`の`names`も必ず同時に更新する |
| 計測中に重いアドホックSQLを回し続けてベンチに影響 | 分析はベンチ終了後に行う（alp/slow-queryと同じ運用） |
