---
name: isucon-server-tuning
description: ISUCONでMySQL・nginx・アプリサーバー（puma/unicorn）の設定チューニングや、複数台構成への分割（DB分離・アプリ複数台）を行うときに使う。「DBを2台目に移して」「nginxをチューニングして」「複数台構成にして」「my.cnfを調整して」などのリクエストで使用する。
---

# ISUCON サーバーチューニング・複数台構成

## 概要

インフラ設定の変更は `make get-conf` で取得した `s1/` `s2/` `s3/` 以下のファイルを編集し、
`make bench`（内部で `deploy-conf`）で反映する。**サーバー上の /etc を直接編集しない**（git管理から外れて再現できなくなる）。

設定変更も計測が前提: nginx側は alp の `reqtime - apptime` 差、DB側は slow-query とCPU使用率（`dstat` / `top`）で判断する。

## MySQL（sN/etc/mysql/ 以下を編集）

```ini
[mysqld]
# バッファプール: 専用DBサーバーならメモリの60-70%、アプリ同居なら控えめに
# （例はメモリ4GB想定。free -h で実メモリを確認して決める）
innodb_buffer_pool_size = 2G

# コミット毎fsyncをやめる（クラッシュ耐性と引き換え。ISUCONでは定番）
innodb_flush_log_at_trx_commit = 2
sync_binlog = 0

# バイナリログが有効ならば無効化（MySQL 8はデフォルト有効）
disable-log-bin
```

- 接続数エラー（Too many connections）が出たら `max_connections` を増やし、アプリ側の接続プールと辻褄を合わせる
- **スロークエリログ（long_query_time=0）は計測時のみ有効。最終ベンチ前に無効化する**（isucon-final-check スキル）

## nginx（sN/etc/nginx/ 以下を編集）

```nginx
# nginx.conf
worker_processes auto;
events {
    worker_connections 4096;
}
http {
    keepalive_timeout 65;

    # アプリへのupstream keepalive（毎回TCP接続を張り直さない）
    upstream app {
        server 127.0.0.1:8080;
        keepalive 128;
    }
    server {
        location / {
            proxy_pass http://app;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
        # 静的ファイルはnginxが直接配信（パスは問題に合わせる）
        location ~ ^/(assets|css|js|images)/ {
            root /home/isucon/webapp/public;
            expires 24h;
            add_header Cache-Control "public, max-age=86400";
        }
        # アプリが書き出した画像を優先し、なければアプリへ（isucon-optimization-patterns パターン5）
        # root のパスは問題の構成に合わせる
        location /image/ {
            root /home/isucon/webapp/public;
            try_files $uri @app;
        }
    }
}
```

- アプリがUNIXソケットをlistenできるなら `server unix:/tmp/app.sock;` の方が速い（アプリ側の設定も必要）
- ltsvログフォーマット（alp用）を消さないこと。計測できなくなる

## アプリサーバー（puma / unicorn）

- ワーカー数はコア数程度から調整（`nproc` で確認）。CPUが余っているのにスループットが出ないなら増やす
- 設定ファイルは `webapp/ruby` 以下（puma.rb / unicorn.rb）またはsystemdユニットの起動コマンドにある
- systemdユニットを変更した場合は `sudo systemctl daemon-reload` が必要（`make restart` に含まれる）

## 複数台構成への分割

典型: **s1 = nginx + アプリ、s2 = DB専用、s3 = アプリ追加**。分割は「1台のCPU/メモリが飽和している」ことを `dstat` / `top` で確認してから行う。

### DBをs2に分離する手順

1. s2で `make setup` / `make set-as-s2` / `make get-conf` 済みであることを確認（README参照）
2. s2の `s2/etc/mysql/` で `bind-address = 0.0.0.0` にする（デフォルトは127.0.0.1で外部から繋がらない）
3. アプリ用MySQLユーザーがリモート接続可能か確認: `CREATE USER 'isucon'@'%' ...` / `GRANT`
4. s1の `s1/env.sh` のDBホスト環境変数（`ISUCON_DB_HOST` 等、問題により名前が異なる）をs2のプライベートIPに変更
5. push → 各サーバーで `git pull && make deploy-conf && make restart` で反映（次のベンチ直前なら `make bench` にまとめても良い。ただし他メンバーの計測を破壊しないこと）
6. s1のMySQL、s2のnginx/アプリなど**使わないサービスは止める**: `sudo systemctl disable --now <DB_SERVICE_NAME>`（サービス名は `mysql` / `mariadb` 等、Makefileの `DB_SERVICE_NAME` に合わせる。空いたメモリをbuffer_poolに回す）

### アプリを複数台に広げる手順

1. s1のnginxの `upstream` にs3を追加:
   ```nginx
   upstream app {
       server 127.0.0.1:8080 weight=1;
       server <s3のプライベートIP>:8080 weight=1;
       keepalive 128;
   }
   ```
2. s3のアプリのlistenを `0.0.0.0` にし、DB接続先をs2に向ける（env.sh）
3. **セッション/キャッシュがプロセス内メモリ前提だと複数台で壊れる**。先に外部化（DB/クッキー）するか、セッションに依存しないエンドポイントだけを振り分ける
4. デプロイは全台に必要: CIの自動デプロイ or `make remote-deploy-all`

## よくある失敗

| 失敗 | 対策 |
|---|---|
| /etc を直接編集して再現不能になる | `sN/` 以下を編集し `deploy-conf` で反映する |
| bind-address / GRANT 忘れでDB分離後に接続不能 | 分割手順2-3を必ず確認。`mysql -h <IP> -u isucon -p` で疎通確認 |
| initialize が s1 の localhost DB を初期化し続ける | initialize処理のDB接続先も env.sh 経由か確認する |
| プロセス内キャッシュ/セッションのまま複数台化して整合性エラー | 先に外部化してから振り分ける |
| 遊んでいるサーバーのmysql/nginxがメモリを食う | 使わないサービスは `disable --now` で止める |
| buffer_pool を盛りすぎてOOM Killerに殺される | `free -h` で実メモリを確認して6-7割に留める |
