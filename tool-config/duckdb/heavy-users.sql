-- ユーザー負荷分布: ユーザーごとのリクエスト数・総reqtime。
-- 少数ユーザーへの集中が見えれば、ベンチマーカーのシナリオ構造（重い動線）の推定材料になる。
-- 上位ユーザーのuseridを控えて、アドホックSQLでそのユーザーの行動を時系列に追うのが定石。
SELECT
  userid,
  count(*)                  AS requests,
  round(sum(reqtime), 1)    AS total_reqtime,
  round(avg(reqtime), 3)    AS avg_reqtime,
  count(DISTINCT uri_norm)  AS distinct_endpoints,
  min(ts)                   AS first_seen,
  max(ts)                   AS last_seen
FROM access_log
WHERE userid IS NOT NULL
GROUP BY 1
ORDER BY total_reqtime DESC
LIMIT 20;
