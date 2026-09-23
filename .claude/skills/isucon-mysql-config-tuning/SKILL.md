---
name: isucon-mysql-config-tuning
description: ISUCONでMySQL（MariaDB含む）の設定ファイルを、サーバーのメモリ・データサイズ・バージョンを計測したうえでISUCON向けに最適化する（buffer pool、バイナリログ無効化、fsync削減、max_connections、DB分離時のbind-address等）。「MySQLの設定をチューニングして」「my.cnfを最適化して」「innodb_buffer_pool_sizeを上げて」「DBを別サーバーに分けたので接続できるようにして」などのリクエストで使用する。インデックス追加・クエリ改善・N+1解消・スロークエリ解析は担当しない（アプリ層/計測の作業）。
---

# ISUCON向けMySQL設定の最適化

MySQLの設定値をISUCON用に変える。**値は推測で決めず、対象サーバーで計測した結果から決める。**
変更は `sN/etc/mysql/` 配下（`make setup-sN` の `get-conf.sh` でサーバーから取り込んだもの）に入れ、`scripts/deploy-conf.sh` でサーバーへ反映する。

設定はテンプレート [references/99-isucon.cnf](references/99-isucon.cnf) を元に、**既存の `mysqld.cnf` は書き換えず `99-isucon.cnf` を追加して上書きする**（差分がこのファイルだけに閉じ、何を変えたか一目で分かる）。

## 前提

- `scripts/vars.sh` の `DB_SERVICE_NAME` が実サーバーと一致していること（ズレていれば `isucon-service-name-setup` スキルを先に実施）
- DBが動いているサーバー（`sN`）を特定していること。DBを分離した場合、設定を置くのは**DBが動くサーバーの** `sN/etc/mysql/`

## 手順

### 1. バージョンと設定ファイルの構成を確認する（読み取りのみ）

```bash
ssh s1 "mysqld --version; ls -R /etc/mysql; grep -rn includedir /etc/mysql"
```

- MySQL 8.0 → `/etc/mysql/mysql.conf.d/` に置く。8.0.30以降かどうかでredoログの変数名が変わる（テンプレートのコメント参照）
- MariaDB → `/etc/mysql/mariadb.conf.d/` に置く。`disable_log_bin` / `innodb_redo_log_capacity` は存在しないので削除し、`innodb_log_file_size` を使う
- `includedir` で読まれるディレクトリであることを確認する（読まれない場所に置くと黙って無視される）

### 2. 値を決めるための計測をする（読み取りのみ）

**データサイズは初期化後・ベンチ後に測る**（ベンチ中にデータが増えるため）。一度ベンチを回してから実行する。

```bash
# CPU・メモリ・メモリを食っているプロセス（アプリ同居かどうか）
ssh s1 "nproc; free -h; ps -eo rss,comm --sort=-rss | head -10"

# スキーマごとのデータ+インデックスサイズ（MB）
ssh s1 "sudo mysql -e \"SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024) AS mb FROM information_schema.tables WHERE table_schema NOT IN ('mysql','sys','information_schema','performance_schema') GROUP BY table_schema\""

# 現在の設定値
ssh s1 "sudo mysql -e \"SHOW VARIABLES WHERE Variable_name IN ('version','innodb_buffer_pool_size','log_bin','innodb_flush_log_at_trx_commit','innodb_doublewrite','innodb_flush_method','innodb_redo_log_capacity','innodb_log_file_size','max_connections','performance_schema','bind_address')\""

# 接続数の実績（ベンチ後）。Max_used_connections が max_connections に張り付いていたら足りていない
ssh s1 "sudo mysql -e \"SHOW GLOBAL STATUS WHERE Variable_name IN ('Max_used_connections','Aborted_connects','Connection_errors_max_connections')\""
```

アプリ側のコネクション数も確認する（`webapp/ruby` の Puma/Unicorn のworker数・thread数、コネクションプールの設定）。

### 3. `99-isucon.cnf` を作成する

[references/99-isucon.cnf](references/99-isucon.cnf) を `sN/etc/mysql/mysql.conf.d/99-isucon.cnf`（MariaDBは `mariadb.conf.d/`）にコピーし、`<...>` を手順2の計測結果で埋める。

| 設定 | 決め方 |
|---|---|
| `innodb_buffer_pool_size` | データサイズが収まる値。上限はDB専用なら物理メモリの70〜80%、アプリ同居なら他プロセスの常駐メモリを引いた残りの半分程度。**大きくしすぎてswap/OOMすると逆効果** |
| `max_connections` | アプリの最大同時接続数（プロセス数×スレッド数×プール）+余裕。手順2で`Max_used_connections`が上限に張り付いていたら上げる |
| `innodb_redo_log_capacity` / `innodb_log_file_size` | バージョンに合う方だけ残す（手順1） |
| `bind-address` 等 | DBを別サーバーに分離したときだけコメントアウトを外す。接続元アプリの`DB_HOST`の変更と、MySQLユーザーのホスト許可（`'isucon'@'%'`等）も必要 |

テンプレートにない変数を追加する場合は、その変数がバージョンに存在するかを公式ドキュメントで確認する（MySQL 8.0 で削除された `query_cache_size` 等を書くと **mysqldが起動しなくなる**）。

### 4. 反映して、効いているか確認する

commit・push したら、ローカルから反映する（`git pull` → `deploy-conf.sh` → DB/アプリ/nginx全再起動）。

```bash
make remote-deploy-conf-s1   # DBが s1 以外ならそのサーバー
```

反映後、**起動していること**と**値が反映されていること**を必ず確認する。

```bash
ssh s1 "systemctl is-active mysql || sudo journalctl -u mysql -n 50 --no-pager"   # DB_SERVICE_NAME に合わせる
ssh s1 "sudo mysql -e \"SHOW VARIABLES WHERE Variable_name IN ('innodb_buffer_pool_size','log_bin','innodb_flush_log_at_trx_commit','innodb_doublewrite','innodb_flush_method','innodb_redo_log_capacity','innodb_log_file_size','max_connections','performance_schema')\""
```

### 5. ベンチで効果を計測する

`make remote-bench-prep-s1` → ベンチ実行 → スコアを変更前と比較する（`make save-bench-log` で結果を残す）。
併せて `make slow-query` の結果が出ること（performance_schemaが生きていること）を確認する。スコアが下がった・エラーが増えた場合は手順6で戻す。

### 6. 戻すとき

`deploy-conf.sh` は `cp` で上書きするだけで**サーバー上のファイルを削除しない**。`sN/` から `99-isucon.cnf` を消しても、サーバーには残り続ける。

```bash
ssh s1 "sudo rm /etc/mysql/mysql.conf.d/99-isucon.cnf && sudo systemctl restart mysql"
```

値を一部戻すだけなら、`99-isucon.cnf` を編集して手順4をやり直せばよい。

## 最終ベンチ前

- `performance_schema = OFF` にすると計測オーバーヘッドが消える。ただし以後 `make slow-query` は使えなくなるので、最後に1回だけ行う
- 再起動試験に備え、`sudo reboot` 後にMySQLが自動起動し、データが残っていることを確認する（`innodb_flush_log_at_trx_commit = 2` は正常な再起動ではデータを失わない）

## よくある失敗

| 失敗 | 対策 |
|---|---|
| 存在しない変数・バージョン違いの変数を書いてmysqldが起動しない | 手順1でバージョンを確認し、手順4で `systemctl is-active` と `journalctl` を必ず見る |
| `sN/etc/mysql/` 直下など `includedir` の対象外に置き、設定が黙って無視される | 手順1で `includedir` を確認し、手順4で `SHOW VARIABLES` で値を確認する |
| `innodb_buffer_pool_size` をメモリいっぱいにして、アプリ同居のサーバーでswap/OOM | 手順2で他プロセスの常駐メモリを測ってから決める |
| データサイズをベンチ前（初期データのみ）で測り、buffer poolが足りない | 一度ベンチを回した後に測る |
| `performance_schema = OFF` にして `make slow-query` が空になる | 競技中はONのまま。OFFは最終ベンチ前だけ |
| DB分離後、`bind-address` を変えたのにアプリから繋がらない | MySQLユーザーのホスト許可（`'isucon'@'localhost'` しかない等）と、アプリ側の `DB_HOST`（`sN/env.sh`）も確認する |
| `sN/` からファイルを消して「戻した」つもりがサーバーに残っている | 手順6のとおりサーバー上のファイルも削除する |
| DBが別サーバーなのに `s1/etc/mysql/` を編集している | DBが動くサーバーの `sN/etc/mysql/` を編集する |
