# 静的ファイルのnginx直接配信とキャッシュヘッダ

Rubyアプリ（Sinatra/Rack）が静的ファイルを返していると、アプリのworkerが静的ファイル配信に占有され、動的リクエストが待たされる。nginxから直接返し、必要ならブラウザキャッシュを効かせる。

## 適用する兆候

- alpで`/assets/*` `/css/*` `/js/*` `/img/*` `/favicon.ico` `/index.html`等の静的パスの`COUNT`・`SUM`が上位
- alpの静的パスの`apptime`（upstream_response_time）が記録されている＝アプリまで届いている
- 静的パスのレスポンスが毎回200（304になっていない）

## 手順1: 静的ファイルの実体を確認する

```bash
# アプリの public ディレクトリ・フロントエンドのビルド成果物の場所を探す
ssh s1 "ls -la /home/isucon/webapp/public 2>/dev/null; find /home/isucon/webapp -maxdepth 3 -type d -name public"
```

alpに出ているパスと実ファイルが1対1で対応するか確認する。**`/image/:id`のようにファイルに見えて実はアプリがDBから返しているパスもある**ので、実ファイルが存在するパスだけをnginx配信の対象にする。

## 手順2: locationを追加する

`sN/etc/nginx/sites-available/<問題名>.conf`の`server {}`内に追加する。

```nginx
root /home/isucon/webapp/public;   # 手順1で確認したパス

# 拡張子・ディレクトリが明確な静的ファイル
location ~ ^/(assets|css|js|img|fonts)/ {
    expires 1d;                    # Cache-Control: max-age=86400 を付ける
}

location = /favicon.ico {
    expires 1d;
}

# SPAのindex.html（パスを問わずindex.htmlを返す構成の場合のみ）
location / {
    try_files $uri /index.html;
}

# APIはアプリへ
location /api/ {
    proxy_pass http://app;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
}
```

`location`の優先順位（完全一致`=` → 最長前置一致`^~` → 正規表現`~`（記述順）→ 最長前置一致）に注意し、既存の`location`と重なったときにどちらが選ばれるかを確認する。

### ファイルが無ければアプリに回す（実ファイルとアプリ応答が混在するパス）

アップロード画像を一部ファイル化した場合など、「ファイルがあればnginx、無ければアプリ」にしたいときは`try_files`で名前付き`location`へ回す。分岐条件はファイルの有無だけに留め、それ以上の判定はアプリに持たせる。

```nginx
location /image/ {
    root /home/isucon/webapp/public;
    try_files $uri @app;
    expires 1d;
}

location @app {
    proxy_pass http://app;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
}
```

画像をDBからファイルに移す実装や、アプリが`X-Accel-Redirect`ヘッダで配信ファイルを指示する実装は**アプリ側の変更**であり本スキルの範囲外。nginx側は`internal`な`location`を用意するだけにする。

```nginx
# アプリが X-Accel-Redirect: /internal-image/xxx.jpg を返したときだけ使われる
location /internal-image/ {
    internal;
    alias /home/isucon/webapp/images/;
}
```

## 手順3: キャッシュヘッダを付けるか判断する

`expires`でブラウザキャッシュさせると、ベンチマーカーがキャッシュを尊重する場合リクエスト自体が減る。一方、**内容が変わり得るリソースをキャッシュさせると整合性チェックで失敗・失格になる**ことがある。

- マニュアルにキャッシュの扱い（`Cache-Control`を尊重する、304を返してよい、等）が書かれているか確認する。`docs/score-model.md`があればその「制約」欄を見る（`isucon-score-strategy`）
- 更新されないビルド成果物（`/assets/`等）には付けてよいことが多い
- ユーザーが変更できるリソース（アイコン画像等）は、マニュアルで許されている範囲・秒数に従う。分からなければ付けない

`expires`の代わりにETag/Last-Modifiedによる304応答だけに頼る方法もある（nginxは静的ファイルに対してデフォルトで付与する）。

## 事前圧縮（任意）

CSS/JSが大きく、ベンチマーカーが`Accept-Encoding: gzip`を送る場合、事前に`.gz`を作っておけば圧縮CPUを使わずに済む。

```nginx
location ~ ^/(assets|css|js)/ {
    gzip_static on;
    expires 1d;
}
```

```bash
# サーバー上で。元ファイルを残して .gz を並べる
find /home/isucon/webapp/public -type f \( -name '*.js' -o -name '*.css' -o -name '*.svg' \) -exec gzip -k -9 -f {} \;
```

## 確認

```bash
ssh s1 "sudo nginx -t"
# ヘッダ確認（Cache-Control / Content-Encoding / 200 or 304）
ssh s1 "curl -sI http://localhost/assets/<実在するファイル> ; curl -sI -H 'Accept-Encoding: gzip' http://localhost/assets/<実在するファイル>"
```

ベンチ後、alpで静的パスの`apptime`が空（アプリに届いていない）になり、動的エンドポイントの`AVG`が下がっていれば効いている。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `root`のパスが違い全静的ファイルが404 | `curl -sI`で200を確認してからベンチを回す。`root`と`alias`の違い（`alias`はlocationのパス部分を置き換える）に注意 |
| 正規表現`location`が既存の`location /api/`より先にマッチして、APIの一部がnginxで404 | 正規表現は前置一致より優先される。パターンを絞るか、`location ^~ /api/`で正規表現評価を止める |
| nginx（`www-data`）が`/home/isucon`配下を読めず403 | `namei -l <ファイル>`でパス上のディレクトリの`x`権限を確認する |
| 画像を`expires`でキャッシュさせたら更新後の画像検証で失敗 | マニュアルのキャッシュ規則を確認し、変更され得るリソースから外す |
