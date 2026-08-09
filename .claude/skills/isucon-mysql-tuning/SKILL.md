---
name: isucon-mysql-tuning
description: ISUCONでMySQLの設定ファイル（my.cnf）をチューニングするときに使う。DBのiowaitが高い・書き込みが遅い・Too many connectionsが出る・buffer pool不足・make slow-queryのクエリが切り詰められる、といった症状で使う。「my.cnfを調整して」「MySQLをチューニングして」「DBのディスクI/Oが高い」「接続数エラーが出た」などのリクエストで使用する。
---

# ISUCON MySQL設定チューニング

## 概要

`make get-conf` で取得した `sN/etc/mysql/` 以下を編集し、push → `make bench`（内部で `deploy-conf`）で反映する。**サーバー上の /etc を直接編集しない**（git管理から外れて再現できなくなる）。

設定を触る前に必ず症状を計測で確認する: `make slow-query`（クエリ側）、`dstat` / `top`（CPU・iowait）、`free -h`（メモリ）。
**DBのCPUが高く、slow-queryで特定クエリにpctが集中している場合、設定では直らない。** 先にインデックス/N+1解消（isucon-optimization-patterns スキル）。設定チューニングが効くのは「クエリは妥当なのにI/O・メモリ・接続数で頭打ち」のとき。

DBを別サーバーに分離する・bind-address等の複数台まわりは isucon-server-tuning スキルを参照。

## 症状 → 設定 対応表

| 症状（計測での見え方） | 効く設定 | 効果の確認 |
|---|---|---|
| 特定クエリがpct上位・DB CPU高 | 設定では直らない → isucon-optimization-patterns へ | `make slow-query` |
| iowait高・書き込み系（INSERT/UPDATE/COMMIT）が遅い | `innodb_flush_log_at_trx_commit = 2` / `sync_binlog = 0` / `disable-log-bin` | `dstat` の wai 列・dsk/writ が下がる |
| read I/O多・データがメモリに乗り切らない | `innodb_buffer_pool_size` | `SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';` がベンチ中に伸び続けるなら不足 |
| Too many connections | `max_connections`（アプリ側の接続プールと辻褄を合わせる） | `SHOW GLOBAL STATUS LIKE 'Max_used_connections';` |
| GROUP BY / ORDER BY が遅く一時テーブルがディスクに落ちる | `tmp_table_size` / `max_heap_table_size`（セットで） | `SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';` |
| `make slow-query` で長いクエリが `...` で切り詰められる | `max_digest_length` / `performance_schema_max_digest_length`（要再起動） | `make slow-query` の出力 |

## ベース設定（sN/etc/mysql/ 以下に追記）

```ini
[mysqld]
# --- I/O削減（クラッシュ耐性と引き換え。ISUCONでは定番） ---
innodb_flush_log_at_trx_commit = 2
sync_binlog = 0
disable-log-bin          # バイナリログ無効化（MySQL 8はデフォルト有効）

# --- メモリ ---
# 専用DBサーバーならメモリの60-70%、アプリ同居なら控えめに
# （例はメモリ4GB・DB専用想定。free -h で実メモリを確認して決める）
innodb_buffer_pool_size = 2G

# --- 計測 ---
slow_query_log = 0       # 常時OFF。クエリ計測はperformance_schema（make slow-query）で行う
# make slow-query で長いクエリが切り詰められる場合に有効化（要再起動）
# max_digest_length = 4096
# performance_schema_max_digest_length = 4096

# --- 症状が出たら ---
# max_connections = 1024      # Too many connections時。アプリのプール数と整合させる
# tmp_table_size = 64M        # Created_tmp_disk_tables が伸びる時（2つセットで）
# max_heap_table_size = 64M
```

## performance_schemaが使えない場合（MariaDB等）

`make slow-query` の計測ソースはperformance_schema。`sudo mysql -e "SELECT @@performance_schema;"` が `0` なら、まず `sN/etc/mysql/` に `performance_schema = ON` を追加して反映を試す。
有効化できない場合のみ従来方式にフォールバックする: `long_query_time = 0` + `slow_query_log = 1` でスロークエリログを有効化し、`sudo pt-query-digest /var/log/mysql/mysql-slow.log` で集計する。**最終ベンチ前に必ず無効化する**（isucon-final-check スキル）。

## 効果検証

1. `sN/etc/mysql/` を編集 → commit/push
2. `make bench`（`deploy-conf` + 全再起動を含む）でベンチ実行
3. 前後比較: スコア、`make slow-query` の総クエリ時間、`dstat` のiowait/CPU

反映確認は実際の値を見る: `sudo mysql -e "SELECT @@innodb_buffer_pool_size, @@innodb_flush_log_at_trx_commit, @@max_connections;"`

## よくある失敗

| 失敗 | 対策 |
|---|---|
| buffer_pool を盛りすぎてOOM Killerに殺される | `free -h` で実メモリを確認して6-7割に留める。アプリ同居ならさらに控えめに |
| slow_query_log を有効化したまま最終ベンチ | 常時OFF運用（計測はperformance_schema）。フォールバックで有効化したら isucon-final-check で必ず戻す |
| `SET GLOBAL` だけで済ませて再起動試験で設定が消える | `sN/etc/mysql/` に書いて `deploy-conf` で反映するのが正。SET GLOBALは検証用と割り切る |
| my.cnf のtypoでMySQLが起動しない | 反映後に `sudo systemctl status <DB_SERVICE_NAME>` で起動確認。終了間際の初変更は避ける |
| 設定変更したのに効かない（要再起動パラメータ） | `max_digest_length` 等は再起動必須。`make bench` / `make restart` を通す |
