---
name: isucon-nginx-caching
description: ISUCONでnginxのHTTPキャッシュ（proxy_cache）やCache-Controlヘッダーを使ってアプリへのリクエストそのものを減らすときに使う。「nginxでキャッシュして」「proxy_cacheを設定して」「レスポンスをキャッシュしたい」「同じリクエストが何度も来ている」などのリクエストで使用する。
---

# ISUCON nginx HTTPキャッシュ

## 概要

アプリ内キャッシュ（isucon-optimization-patterns パターン3）はアプリプロセスに処理をさせた上で結果を使い回すが、
nginxのHTTPキャッシュは**アプリに一切到達させずにnginxがレスポンスを返す**。効果は大きい分、
**ベンチマーカーが更新直後の値を厳しくチェックする問題では整合性エラーの原因になりやすく、諸刃の剣**。
適用前に「このエンドポイントはどれくらいの間、古い値を返してよいか」をレギュレーションで確認する。

**使い分けの基準**: ユーザー固有情報・認証が絡む、または書き込み系（POST/PUT/DELETE）→ nginxキャッシュ不可、
アプリ内キャッシュ（キー設計でユーザーごとに分離）を検討する。全ユーザー共通でGETのみ・古い値を許容できる
→ nginxキャッシュを第一候補にする（アプリにすら到達させない分、効果が大きい）。両方を同時に使う必要は薄い
（同じデータに二重にキャッシュ層を作ると無効化漏れのリスクが増える）。

## 適用シグナル

- alpで同一URLへの `GET` リクエストが大量かつ、レスポンス内容がリクエスト間でほぼ変わらない
  （マスタデータ・ランキング・他ユーザーには見えても自分では更新しない情報など）
- そのエンドポイントが `POST`/`PUT` 等の副作用を持たない（GETのみ）

**書き込み系（POST/PUT/DELETE）やユーザー固有の認証情報を含むレスポンスには適用しない。**

## 1. アプリ側でCache-Controlヘッダーを付与する

nginxにキャッシュ可否・期間を指示するため、まずアプリ側でヘッダーを制御する。

```ruby
# 例: Sinatraでの設定
get '/api/ranking' do
  cache_control :public, max_age: 5   # 5秒だけキャッシュ許可
  # ...
end
```

## 2. nginx側でproxy_cacheを設定する

```nginx
# http {} ブロック内（sN/etc/nginx/nginx.conf）
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=app_cache:10m max_size=1g inactive=60m use_temp_path=off;

server {
    location /api/ranking {
        proxy_pass http://app;
        proxy_cache app_cache;
        proxy_cache_valid 200 5s;          # アプリのCache-Controlより優先される点に注意
        proxy_cache_key "$scheme$request_method$host$request_uri";
        add_header X-Cache-Status $upstream_cache_status;   # HIT/MISSをレスポンスヘッダーで確認できる
    }
}
```

- `proxy_cache_valid` は明示的に設定した場合、アプリの `Cache-Control` より優先されるのが基本（`proxy_ignore_headers` の設定次第で挙動が変わる場合がある）。両方書く場合は値を一致させ、実際にどちらが効いているかは次項の確認手順で検証する
- `X-Cache-Status` ヘッダーはデバッグ用。**ベンチマーカーが想定外ヘッダーを許容するかレギュレーションで確認し、確認後は消す**（減点リスクを避ける）
- `keys_zone` のメモリサイズ・`max_size` はディスク容量と相談する
- **`POST /initialize` 実行時はnginxのキャッシュもクリアする**: `rm -rf /var/cache/nginx/*` を初期化処理の一部として実行するか、`proxy_cache_path` のディレクトリを初期化スクリプトに組み込む。クリアしないと前回ベンチの古いレスポンスが新しいベンチに漏れて整合性エラーの原因になる

## 3. 効果測定

```bash
make alp   # 対象URLのSUM/AVGが下がっているか
```

nginx自体がキャッシュから返すため、apptime（アプリ応答時間）がほぼ0になっているエンドポイントは
キャッシュがHITしている証拠。reqtimeとapptimeの差で判断する（isucon-bottleneck-analysis参照）。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| ユーザー固有情報を含むレスポンスをキャッシュし、他人に見えてしまう | `proxy_cache_key` にセッション/認証情報を含めるか、そもそも適用しない |
| POST/PUTのような副作用のあるエンドポイントに誤って適用する | GETのみ、かつ副作用がないエンドポイント限定 |
| TTLを長くしすぎて整合性チェックで減点される | レギュレーションの許容範囲を先に確認し、短いTTLから試す |
| `proxy_cache_valid` とアプリの`Cache-Control`が矛盾し混乱する | 両方を確認し、値を揃えるか片方に統一する |
| キャッシュがHITしているか確認せず「設定したから効いているはず」と思い込む | `X-Cache-Status` ヘッダーで実際にHITしているか確認する |
| `POST /initialize` 後もnginxキャッシュに前回ベンチの古いレスポンスが残る | 初期化処理でnginxキャッシュディレクトリもクリアする |
| デバッグ用の `X-Cache-Status` を本番投入後も残し減点される | 確認が済んだらヘッダーを削除する |
