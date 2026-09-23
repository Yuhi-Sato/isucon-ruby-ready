# 複数台への振り分け（upstreamに複数サーバー）

ベンチマーカーは通常s1にだけリクエストを送る。s1のnginxから`upstream`で複数台のアプリへ振り分けると、s2/s3のCPUも使えるようになる。

## 適用する兆候

- ベンチ中にs1のアプリ（ruby/puma）のCPUが張り付き、s2/s3のCPUが遊んでいる
- DBは別サーバーに分離済み、またはs1のDB負荷が低い（アプリを増やすとDB接続も増えるため）

事前に満たすこと（本スキルの範囲外）:

- s2/s3でアプリが起動し、DBに接続できること（`sN/env.sh`のDBホスト等）
- アプリがサーバーローカルに状態を持っていないこと（オンメモリキャッシュ・ローカルファイルへの書き込み・セッションのローカル保存）。持っていると振り分け先によって結果が変わり整合性チェックで落ちる
- s2/s3のアプリのポートにs1から到達できること（`ssh s1 "curl -sI http://<s2のIP>:8080/"`）

## 設定例

s1の`sN/etc/nginx/sites-available/<問題名>.conf`を編集する。

```nginx
upstream app {
    server 127.0.0.1:8080 weight=1;      # s1（nginxと同居しているので軽めに）
    server 192.168.0.12:8080 weight=2;   # s2（プライベートIPを使う）
    server 192.168.0.13:8080 weight=2;   # s3
    keepalive 64;
}
```

`weight`はベンチ中の各サーバーのCPU使用率を見て調整する（使用率が低いサーバーの`weight`を上げる）。

### 特定のエンドポイントだけ別サーバーへ

alpで重いエンドポイントが1つに偏っている場合、そのパスだけを専用サーバーに逃がす。

```nginx
upstream app_heavy {
    server 192.168.0.13:8080;
    keepalive 32;
}

location /api/heavy-endpoint {
    proxy_pass http://app_heavy;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
}
```

### 静的ファイルはs1のnginxから返す

振り分け先に静的ファイルのリクエストまで送らないよう、[static-delivery.md](static-delivery.md)の設定をs1で済ませておく。

## 確認

```bash
ssh s1 "sudo nginx -t"
# ベンチ中、各サーバーのアプリCPUが均等に上がっていること
for s in s1 s2 s3; do echo "== $s"; ssh $s "top -b -n 1 | grep -E 'ruby|puma' | head -5"; done
```

## よくある失敗

| 失敗 | 対策 |
|---|---|
| 振り分けたらスコアが下がった / 整合性エラー | アプリがローカル状態（オンメモリキャッシュ等）を持っていないか確認する。持っているなら振り分けを戻すか、その状態を共有ストアに移す（アプリ側の変更） |
| DBの`Too many connections` | アプリ台数×プール数がDBの`max_connections`を超えていないか確認する |
| s2/s3のアプリが古いコードのまま | `make remote-deploy-all`等で全台に同じブランチをデプロイしてからベンチを回す |
| グローバルIPで振り分けて遅い・課金される | サーバー間はプライベートIPを使う |
