---
name: isucon-nginx-tuning
description: ISUCONでnginxの設定ファイルをチューニングするときに使う。alpでreqtimeとapptimeが乖離している・静的ファイルがSUM上位・"Too many open files"エラー・413/502が出る、といった症状で使う。「nginxをチューニングして」「静的ファイルをnginxで配信して」「UNIXソケットにして」「worker_connectionsを増やして」などのリクエストで使用する。レスポンスのHTTPキャッシュ（proxy_cache/Cache-Control）は isucon-nginx-caching スキルを使う。
---

# ISUCON nginx設定チューニング

## 概要

`make get-conf` で取得した `sN/etc/nginx/` 以下を編集し、push → `make bench`（内部で `deploy-conf`）で反映する。**サーバー上の /etc を直接編集しない**（git管理から外れて再現できなくなる）。

判断材料は3つ: `make alp` の **`reqtime - apptime` 差**（差が大きい＝nginx〜アプリ間で詰まっている）、nginxのエラーログ（`/var/log/nginx/error.log`）、`top` でのnginx CPU。アプリ自体が遅い（apptime大）ならこのスキルではなく isucon-bottleneck-analysis → アプリ/DB改善へ。

同一GETリクエストが大量に来ていてレスポンスをキャッシュできる場合は isucon-nginx-caching スキル、アプリを複数台に広げる場合のupstream振り分けは isucon-server-tuning スキルを参照。

## 症状 → 設定 対応表

| 症状（計測での見え方） | 効く設定 | 効果の確認 |
|---|---|---|
| reqtime ≫ apptime（nginx〜アプリ間で詰まる） | upstream keepalive（`keepalive` + `proxy_http_version 1.1` + `Connection ""`）、`worker_connections` | `make alp` で差が縮む |
| 静的ファイル（css/js/画像）がalp SUM上位 | nginx直接配信の `location` + `expires`（下記） | 該当URIのapptime ≈ 0、SUM低下 |
| error.logに "Too many open files" / accept失敗 | `worker_rlimit_nofile`（worker_connectionsとセットで） | error.logからエラーが消える |
| localhostへのTCP接続オーバーヘッドを削りたい | UNIXソケット化（下記手順。nginxとアプリ両側の変更が必要） | reqtime - apptime差の微減 |
| レスポンスbodyが大きく帯域がネック | `gzip`（JSON/HTML等テキスト系のみ。画像には効かない） | alp の BODY SUM低下 |
| 画像アップロード等で413 Request Entity Too Large | `client_max_body_size` | ベンチのエラーが消える |
| 同一GETが大量でレスポンスが不変 | isucon-nginx-caching スキルへ | - |

## ベース設定（sN/etc/nginx/nginx.conf）

```nginx
worker_processes auto;
worker_rlimit_nofile 65536;

events {
    worker_connections 4096;
}

http {
    # ltsvログフォーマット（alp用）は消さない。計測できなくなる

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;

    # アプリへのupstream keepalive（毎回TCP接続を張り直さない）
    upstream app {
        server 127.0.0.1:8080;
        keepalive 128;
    }

    server {
        location / {
            proxy_pass http://app;
            # ↓この2行が無いとkeepaliveが効かない（HTTP/1.0 + Connection: closeになる）
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

## UNIXソケット化の手順

localhostのTCPよりUNIXソケットの方が速い。**nginxとアプリの両側を同時に変更する。**

1. アプリ側（puma）: `webapp/ruby/puma.rb` 等で `bind "unix:///tmp/app.sock"` にする（systemd起動コマンドでポート指定している場合はそちらも。isucon-puma-tuning スキル参照）
2. nginx側: `upstream app { server unix:/tmp/app.sock; keepalive 128; }`
3. 反映後、ソケットファイルの存在とパーミッションを確認: `ls -l /tmp/app.sock`（nginxのworkerユーザーが読み書きできること）

## 効果検証

1. `sN/etc/nginx/` を編集 → commit/push
2. `make bench`（`deploy-conf` + 全再起動を含む）でベンチ実行
3. 前後比較: スコア、`make alp` の reqtime / apptime / BODY SUM

構文チェックはサーバー上で `sudo nginx -t`。反映確認は `nginx -T | grep <設定名>` で実際の値を見る。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `proxy_http_version 1.1` / `Connection ""` を忘れてkeepaliveが効いていない | upstream keepaliveは3点セット。`netstat -tan \| grep 8080 \| wc -l` でTIME_WAIT大量なら効いていない |
| ltsvログフォーマットを消して計測不能になる | `log_format ltsv` とaccess_log行は必ず残す |
| 静的配信の `root` パス誤りで404・ベンチFAIL | `root` + URIの結合結果が実ファイルパスになるか確認（`alias` との違いに注意） |
| UNIXソケットのパーミッションで502 | `ls -l` で確認。アプリの起動ユーザーとnginxユーザーの両方がアクセスできること |
| worker_connections だけ増やして "Too many open files" | `worker_rlimit_nofile` もセットで増やす |
| gzipを画像に適用してCPUを無駄に食う | 対象は `gzip_types` でテキスト系MIMEに限定する |
