-- リピート検出: 同一ユーザーが同一URI（クエリ文字列含む）を複数回GETしているパターンの集計。
-- 2回目以降のリクエスト（repeat_hits）はキャッシュで潰せる可能性がある
-- （ユーザー内キャッシュ・304・Cache-Control。isucon-nginx-caching スキル参照）。
-- repeat_reqtime_sumが大きいuri_normがキャッシュ機会の最有力候補。
WITH per_user_uri AS (
  SELECT
    userid,
    uri,
    uri_norm,
    count(*)     AS hits,
    sum(reqtime) AS total_reqtime
  FROM access_log
  WHERE userid IS NOT NULL AND method = 'GET' AND status < 400
  GROUP BY 1, 2, 3
  HAVING count(*) >= 2
)
SELECT
  uri_norm,
  count(DISTINCT userid)                            AS users,
  sum(hits)                                         AS total_hits,
  sum(hits - 1)                                     AS repeat_hits,
  round(sum(total_reqtime * (hits - 1) / hits), 1)  AS repeat_reqtime_sum
FROM per_user_uri
GROUP BY 1
ORDER BY repeat_reqtime_sum DESC
LIMIT 30;
