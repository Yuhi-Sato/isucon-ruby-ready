-- LTSVアクセスログをaccess_logテーブル（VIEW）として見せる定義。
-- 全レシピ・アドホック分析の前提としてこれを最初に読み込む。
-- カラムの順序は tool-config/nginx/ltsv-log-format.conf の log_format と一致させること。

-- LTSVの "key:value" から先頭の "key:" を剥がす（値に':'を含むtimeにも安全）
CREATE OR REPLACE MACRO ltsv_val(s) AS regexp_replace(s, '^[a-z]+:', '');

CREATE OR REPLACE VIEW access_log AS
SELECT
  strptime(ltsv_val(c_time), '%d/%b/%Y:%H:%M:%S %z')          AS ts,        -- リクエスト完了時刻（1秒精度）
  strptime(ltsv_val(c_time), '%d/%b/%Y:%H:%M:%S %z')
    - to_microseconds(CAST(try_cast(ltsv_val(c_reqtime) AS DOUBLE) * 1e6 AS BIGINT))
                                                               AS start_ts,  -- リクエスト開始時刻（近似）
  ltsv_val(c_host)                                             AS host,
  ltsv_val(c_method)                                           AS method,
  ltsv_val(c_uri)                                              AS uri,
  -- 数値のパスセグメントを:idに正規化し、クエリ文字列を落とす。
  -- UUID等の非数値IDが出る問題では当日ここに正規化を追記する（alpのmatching_groupsと同じ趣旨）
  regexp_replace(regexp_replace(ltsv_val(c_uri), '\?.*$', ''), '/\d+(/|$)', '/:id\1', 'g')
                                                               AS uri_norm,
  try_cast(ltsv_val(c_status) AS INTEGER)                      AS status,
  try_cast(ltsv_val(c_size) AS BIGINT)                         AS size,
  try_cast(ltsv_val(c_reqtime) AS DOUBLE)                      AS reqtime,
  try_cast(ltsv_val(c_apptime) AS DOUBLE)                      AS apptime,
  nullif(ltsv_val(c_cache), '-')                               AS cache,
  nullif(ltsv_val(c_userid), '-')                              AS userid    -- 未ログイン・静的ファイルはNULL
FROM read_csv(
  '/var/log/nginx/access.log',
  delim = '\t', header = false, quote = '', escape = '',
  all_varchar = true, null_padding = true,
  names = ['c_time', 'c_host', 'c_forwardedfor', 'c_req', 'c_status', 'c_method', 'c_uri',
           'c_size', 'c_referer', 'c_ua', 'c_reqtime', 'c_apptime', 'c_cache', 'c_vhost', 'c_userid']
);
