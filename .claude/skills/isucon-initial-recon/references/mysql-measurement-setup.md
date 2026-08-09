# MySQL計測設定（performance_schema / slow_query_log）のセットアップ

`make slow-query` の計測ソースはperformance_schema。有効化されていないと、N+1やスロークエリの分析ができない。**初動調査でベースラインを取る前に必ず確認する。**

## 手順

1. 有効化状況を確認する

   ```bash
   sudo mysql -e "SELECT @@performance_schema;"   # 1ならOK
   ```

2. `0` の場合（MariaDB出題など）: `make get-conf` 後に `sN/etc/mysql/` へ `performance_schema = ON` を追加してcommit・push → `make bench-prep` で反映する
3. 有効化できない場合は従来方式にフォールバックする: `long_query_time = 0` でslow logを有効化し `sudo pt-query-digest /var/log/mysql/mysql-slow.log` で集計する（isucon-mysql-tuning スキル参照）
4. `slow_query_log` は**常時OFF運用**にする（計測はperformance_schemaで行うためスロークエリログは不要。I/O削減でスコアにも効く）。`sN/etc/mysql/` へ `slow_query_log = 0` を明示しておく

my.cnfの他のチューニング項目（buffer pool・接続数等）は isucon-mysql-tuning スキルを参照。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| performance_schemaが無効なまま `make slow-query` を実行し、結果が空になる | ベースライン計測前に手順1で確認する |
| フォールバックでslow_query_logを有効化したまま最終ベンチに突入する | isucon-final-check スキルで必ずOFFに戻す |
| `SET GLOBAL` だけで済ませて再起動試験で設定が消える | `sN/etc/mysql/` に書いて `deploy-conf`（`make bench-prep`に含まれる）で反映するのが正 |
