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
