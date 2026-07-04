-- 遷移分析: ユーザーごとにリクエストを時系列に並べ、「URI → 次のURI」の遷移ペアを集計する。
-- 支配的な行動フロー（一覧→詳細→購入など）と、フロー中のどの区間が遅いかを見る。
-- ※ timeは1秒精度のため同一秒内の順序は近似。集計ベースの遷移分析には十分。
WITH seq AS (
  SELECT
    userid,
    uri_norm,
    reqtime,
    lead(uri_norm) OVER (PARTITION BY userid ORDER BY start_ts, ts) AS next_uri,
    lead(reqtime)  OVER (PARTITION BY userid ORDER BY start_ts, ts) AS next_reqtime
  FROM access_log
  WHERE userid IS NOT NULL
)
SELECT
  uri_norm                          AS from_uri,
  next_uri                          AS to_uri,
  count(*)                          AS transitions,
  round(avg(next_reqtime), 3)       AS to_avg_reqtime,
  round(sum(next_reqtime), 1)       AS to_sum_reqtime
FROM seq
WHERE next_uri IS NOT NULL
GROUP BY 1, 2
ORDER BY transitions DESC
LIMIT 30;
