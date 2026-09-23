# nginx → アプリ（upstream）のkeepalive

初期設定の多くは`proxy_pass http://127.0.0.1:8080;`のように直接宛先を書いており、nginx→アプリ間が**リクエストごとにTCP接続を張り直す**。`upstream`ブロックで`keepalive`を有効にすると接続を再利用でき、全エンドポイントのレイテンシが一律に下がる。

## 適用する兆候

- ベンチ中に`ss -tan state time-wait | wc -l`が数千〜数万ある（アプリのポート宛）
- `proxy_pass`が`upstream`を経由していない、または`upstream`に`keepalive`が無い
- error.logに`connect() failed (99: Cannot assign requested address)`（エフェメラルポート枯渇）

## 設定例

`sN/etc/nginx/sites-available/<問題名>.conf`（`include`されている実体）を編集する。

```nginx
upstream app {
    server 127.0.0.1:8080;      # 既存のproxy_pass先に合わせる
    keepalive 64;               # workerごとに保持するアイドル接続数
    keepalive_requests 10000;   # upstream内で書けるのはnginx 1.15.3以降
}

server {
    ...
    location / {
        proxy_pass http://app;
        proxy_http_version 1.1;          # keepaliveにはHTTP/1.1が必須
        proxy_set_header Connection "";  # "close"を送らせない
        proxy_set_header Host $host;     # 既存のproxy_set_headerを全部ここに並べる
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

`proxy_set_header`は**同じブロックに1つでも書くと上位（`server`/`http`）の定義を全部継承しなくなる**。既存設定にあったヘッダ（`Host`・`X-Forwarded-For`・`X-Forwarded-Proto`等）は漏れなく同じブロックに書き直す。

複数の`location`が同じアプリへ中継している場合は、すべての`location`で`proxy_pass http://app;`と上記2行を揃える。

`keepalive`の値はアプリ側の同時処理数（pumaの`workers × threads`）を目安にする。アプリ側が保持できる以上の接続を持たせても意味がない。

## Unixドメインソケット（任意・アプリ側の変更を伴う）

同一サーバー内ならTCPの代わりにUnixドメインソケットでつなぐとさらにオーバーヘッドが減る。ただし**pumaの`bind`（アプリの起動設定）を変える必要がある**ので、nginx単体の変更では完結しない。keepaliveを入れた上で、まだnginx↔アプリ間がボトルネックだと計測で分かった場合のみ検討する。

```nginx
upstream app {
    server unix:/run/isucon/puma.sock;   # pumaのbind先と一致させる
    keepalive 64;
}
```

注意点:

- ソケットのパーミッション: nginxの実行ユーザー（`www-data`等）が読み書きできること
- systemdユニットに`PrivateTmp=true`があると`/tmp`がプロセスごとに分離され、nginxからソケットが見えない。`/tmp`以外（例: `/run/<ディレクトリ>`）に置く
- systemdユニットは`sN/`で管理されていない。起動コマンドを変える場合は、アプリのリポジトリ内の設定（`config/puma.rb`等）か`sN/env.sh`で切り替えられる形にし、再現できるようにする

## 確認

```bash
ssh s1 "sudo nginx -t"
# ベンチ中、アプリポート宛のESTABLISHEDが一定数で再利用され、TIME_WAITが激減していること
ssh s1 "ss -tan state time-wait | wc -l; ss -tan state established '( dport = :8080 )' | wc -l"
```

alpで全体的に`MIN`・`AVG`が下がっていれば効いている。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `keepalive`を書いたが`TIME_WAIT`が減らない | `proxy_http_version 1.1;`と`proxy_set_header Connection "";`が全`location`に入っているか確認する |
| `proxy_set_header Connection "";`を足したら`Host`ヘッダが`app`になりアプリが誤動作 | 継承が切れている。`Host $host`を同じブロックに書く |
| WebSocket/SSEのエンドポイントまで`Connection ""`になって切れる | そのパスだけ別`location`にし、`Upgrade`/`Connection "upgrade"`ヘッダを付ける |
| Unixソケットに変えたら502 | error.logの`connect() to unix:... failed`を確認する。パス・パーミッション・`PrivateTmp`を疑う |
