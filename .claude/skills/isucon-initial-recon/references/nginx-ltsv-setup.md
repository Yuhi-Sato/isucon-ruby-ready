# nginx ltsvログフォーマットのセットアップ

問題の初期nginx.confは`combined`等の標準フォーマットで、`make alp`が読めるltsv形式になっていないことが多い。**初動調査でベースラインを取る前に必ず反映する**（後から入れると、それ以前のベンチのalpデータが取れない）。

## 手順

1. `tool-config/nginx/ltsv-log-format.conf` の内容を `sN/etc/nginx/nginx.conf` の `http {}` ブロック内に貼り付ける（`log_format ltsv ...` 定義）
2. `server {}` 内の `access_log` をltsv形式に変更する: `access_log /var/log/nginx/access.log ltsv;`
3. アプリへproxyする `location` に `proxy_hide_header X-User-Id;` を追加する（ユーザー行動履歴ロガーを使う場合。isucon-user-behavior-analysis スキル参照。使わない場合は不要）
4. commit・push → `make bench-prep` で反映 → `make alp` が正常に集計できることを確認する

nginx設定の他のチューニング項目（keepalive・静的配信・UNIXソケット等）は isucon-nginx-tuning スキルを参照。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| ltsvログフォーマットが未反映・削除されて `make alp` が使えない | `log_format ltsv` とltsvな`access_log`行を必ず入れる・残す |
| `proxy_hide_header X-User-Id;` を入れ忘れ、ベンチマーカーへのレスポンスにヘッダーが漏れる | ユーザー行動履歴ロガーを使う場合は3を忘れずに行う |
| 構文ミスで `nginx -t` が通らない | 反映前にサーバー上で `sudo nginx -t` を実行して確認する |
