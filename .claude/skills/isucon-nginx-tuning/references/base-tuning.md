# nginx.conf の基本チューニング（worker・接続数・送信・バッファ）

`sN/etc/nginx/nginx.conf`のトップレベル・`events {}`・`http {}`に入れる定番設定。値は出発点であり、error.logの兆候を見て増減する。

## 適用する兆候

- ベンチ中の`top`でnginxのworkerがCPUを使い切っている、またはworker数が`nproc`より少ない
- error.logに`worker_connections are not enough` / `Too many open files` / `accept4() failed (24: Too many open files)`
- error.logに`an upstream response is buffered to a temporary file` / `a client request body is buffered to a temporary file`
- 413 `Request Entity Too Large`がalpに出ている

## 設定例

既存の値を確認してから差分だけ書き換える（丸ごと置き換えると`include`や`user`等を消してしまう）。

```nginx
user www-data;                  # 既存の値を維持
worker_processes auto;          # CPUコア数に合わせる
worker_rlimit_nofile 65535;     # workerが開けるFD上限（worker_connectionsの2倍以上）

events {
    worker_connections 4096;    # 1workerあたりの同時接続数（クライアント側+upstream側の合計）
    multi_accept on;
}

http {
    # --- 送信 ---
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;

    # --- クライアントとのkeepalive ---
    keepalive_timeout 65;
    keepalive_requests 10000;   # 1接続あたりのリクエスト上限（デフォルト1000）

    # --- アクセスログ（ltsvは残す。バッファリングで書き込み回数を減らす） ---
    access_log /var/log/nginx/access.log ltsv buffer=64k flush=1s;

    # --- ファイルのメタ情報キャッシュ（静的ファイル配信時） ---
    open_file_cache max=10000 inactive=60s;
    open_file_cache_valid 60s;
    open_file_cache_min_uses 1;
    open_file_cache_errors off;  # アプリが後から書くファイルを配るならoffのまま

    include /etc/nginx/mime.types;   # 既存のinclude群は消さない
    ...
}
```

`access_log`のltsv定義は`isucon-measurement-setup`で入れたものを使う。`server {}`側に`access_log`がある場合はそちらにも`buffer=`を付ける（下位ブロックの定義が優先される）。`flush=1s`にしておけばベンチ終了直後に`make alp`しても取りこぼさない。

## gzip（計測してから入れる）

レスポンスが大きい（alpの`AVG(BODY)`が数KB以上）エンドポイントが上位にあり、かつベンチマーカーが`Accept-Encoding: gzip`を送る場合のみ効く。圧縮はnginxのCPUを使うので、nginxのCPUが既に高いなら逆効果になり得る。

```nginx
gzip on;
gzip_comp_level 1;              # 1〜2で十分。上げてもサイズはほぼ縮まずCPUだけ増える
gzip_min_length 1024;
gzip_types application/json text/css application/javascript text/plain image/svg+xml;
gzip_vary on;
gzip_proxied any;               # アプリからのレスポンスも圧縮対象にする
```

静的ファイルは事前圧縮して`gzip_static on;`を使う方がCPUを使わない（[static-delivery.md](static-delivery.md)）。

効果確認: alpの`SUM(BODY)`が減り、nginxのCPU使用率が許容範囲内であること。

## バッファ

error.logに該当メッセージが出ている場合のみ増やす。

```nginx
# upstream(アプリ)のレスポンスが一時ファイルに書かれている
proxy_buffer_size 32k;
proxy_buffers 64 32k;
proxy_busy_buffers_size 64k;

# クライアントのリクエストボディ（画像アップロード等）が一時ファイルに書かれている
client_body_buffer_size 1m;

# 413 Request Entity Too Large が出ている（マニュアル上の最大アップロードサイズに合わせる）
client_max_body_size 10m;
```

## 確認

```bash
ssh s1 "sudo nginx -t"
# workerの数とFD上限が反映されたか
ssh s1 "ps -o pid,user,cmd -C nginx; for p in \$(pgrep -f 'nginx: worker'); do sudo grep 'Max open files' /proc/\$p/limits; break; done"
# ベンチ後、兆候のエラーが消えたか
ssh s1 "sudo tail -n 200 /var/log/nginx/error.log"
```

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `worker_connections`だけ上げて`Too many open files`が出る | `worker_rlimit_nofile`も上げる |
| `gzip`を入れたらnginxのCPUが張り付いてスコアが下がった | `gzip_comp_level`を1にする・静的ファイルは`gzip_static`に切り替える・効果が無ければ戻す |
| `access_log`を`http`で書き換えたのに`server`側の定義が優先されてバッファが効かない | `server {}`・`location {}`内の`access_log`も確認する |
