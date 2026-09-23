---
name: isucon-nginx-tuning
description: ISUCONでnginxの設定（sN/etc/nginx/配下のnginx.conf・sites-available）を計測結果に基づいて最適化する。worker/接続数・upstreamへのkeepalive・静的ファイルの直接配信とキャッシュヘッダ・gzip・プロキシバッファ・複数台への振り分けを扱う。「nginxをチューニングして」「nginxの設定を最適化して」「静的ファイルをnginxから返して」「upstreamのkeepaliveを入れて」「アプリを複数台に振り分けて」などのリクエストで使用する。ltsvログフォーマットの導入は`isucon-measurement-setup`スキルが担当する。アプリのコード変更（画像のDB→ファイル移行など）は行わない。
---

# ISUCON nginx チューニング

## 概要

nginxの設定変更は数行で効くことが多いが、**効かない箇所に入れても点は伸びず、壊すと全リクエストが落ちる**。本スキルは「計測でnginxが効く箇所を特定 → 1項目ずつ反映 → ベンチで比較」の手順と、ISUCONで定番の設定をまとめる。

鉄則（CLAUDE.md）:

- **推測するな。計測せよ。** 設定を入れる根拠（alpの行・error.logの行・topの数値）を必ず添える。根拠のない「定番だから全部入れる」はしない
- **インフラにロジックを書かない。** nginxでやるのは「静的ファイルを返す」「アプリへ中継する」「ヘッダを付ける」まで。`if`/`map`/`rewrite`で認可・分岐・レスポンス生成をしたり、Lua/njsを使ったりしない。分岐が必要ならアプリ側で判定し、nginxは`X-Accel-Redirect`等で指示どおりに返すだけにする

## 対応範囲

| 担当する | 担当しない（別スキル・別作業） |
|---|---|
| `sN/etc/nginx/nginx.conf`・`sN/etc/nginx/sites-available/*`の編集 | ltsvログフォーマットの導入（`isucon-measurement-setup`） |
| 反映（`make remote-bench-prep-sN`）と`nginx -t`・error.logでの確認 | アプリのコード変更（画像のDB→ファイル移行、`X-Accel-Redirect`を返す実装など） |
| alp・error.logを使った効果確認 | マニュアルのキャッシュ規則の解釈（`isucon-score-strategy`） |

## 手順0: 前提を揃える

1. ltsvログが入っていること（`make alp`が動くこと）。未導入なら先に`isucon-measurement-setup`の[nginx-ltsv-setup](../isucon-measurement-setup/references/nginx-ltsv-setup.md)を済ませる。**ベースライン計測前にnginxをいじらない**
2. 変更前のベンチスコアと`make alp`結果（`measure-logs/alp/`）があること。無ければ一度ベンチを回して取る
3. mainからブランチを切る（例: `nginx-tuning`）

## 手順1: 現在の設定を読む

リポジトリ内の`sN/etc/nginx/`を読む（`make setup-sN`時に実サーバーからコピーされている）。

```bash
ls -la s1/etc/nginx/ s1/etc/nginx/sites-available/ s1/etc/nginx/sites-enabled/
ssh s1 "nginx -v 2>&1; nproc; ulimit -n"
```

確認すること:

- **どのファイルが実際に読まれているか**: `nginx.conf`の`include`先（`conf.d/*.conf`・`sites-enabled/*`）。`sites-enabled/`配下は`sites-available/`へのシンボリックリンクのことが多い。リンクのまま編集しようとすると空振りするので、**実体（`sites-available/`側）を編集する**
- `upstream`・`proxy_pass`の宛先（TCPポート / Unixソケット）
- `root`・静的ファイルの`location`があるか
- 既存の`proxy_set_header`（アプリが`X-Forwarded-For`等に依存していないか）
- nginxのバージョン（`http2`・`keepalive_requests`等の書き方が変わる）

## 手順2: nginxが効く箇所を計測で特定する

次の兆候を確認し、該当するreferenceだけを適用する。**兆候が無い項目はやらない。**

| 兆候（計測元） | 疑う原因 | reference |
|---|---|---|
| ベンチ中の`top`でnginxのCPU使用率が高い / error.logに`worker_connections are not enough`・`Too many open files` | worker・接続数・ファイルディスクリプタ不足 | [base-tuning.md](references/base-tuning.md) |
| `ss -s`でアプリポート宛の`TIME_WAIT`が大量 / alpで全エンドポイントの`MIN`が底上げされている | nginx→アプリの接続を毎回張り直している | [upstream-keepalive.md](references/upstream-keepalive.md) |
| alpで`/assets` `/js` `/css` `/image` `/icon`等の静的パスの`COUNT`・`SUM`が上位 | 静的ファイルをアプリ（Ruby）が返している / キャッシュヘッダが無い | [static-delivery.md](references/static-delivery.md) |
| error.logに`buffered to a temporary file` / 413 `Request Entity Too Large` | プロキシ・リクエストボディのバッファ不足 | [base-tuning.md](references/base-tuning.md) の「バッファ」節 |
| s1のアプリCPUが張り付き、s2/s3が遊んでいる | 1台にリクエストが集中している | [load-balancing.md](references/load-balancing.md) |

計測コマンド:

```bash
# ベンチ中に別ターミナルで。nginx / ruby / mysqld のどれがCPUを食っているか
ssh s1 "top -b -d 1 -n 20 | grep -E 'nginx|ruby|puma|mysqld'"
# ベンチ後。nginxのerror.logはbench-prepで消えないので末尾（今回のベンチ時刻）を見る
ssh s1 "sudo tail -n 200 /var/log/nginx/error.log"
# 接続状態の概要（ベンチ中）
ssh s1 "ss -s; ss -tan state time-wait | wc -l"
# エンドポイント別集計
make alp
```

## 手順3: 1項目ずつ反映する

1. referenceに従って`sN/etc/nginx/`配下を編集する。nginxが動いている全サーバー分（`s1/`・`s2/`…）を揃える
2. commit・push → 反映

   ```bash
   make remote-bench-prep-s1 BRANCH=<ブランチ名>
   ```

3. 構文と起動を確認する。**`nginx -t`が通らないままベンチを回さない**（全リクエストが落ちて0点）

   ```bash
   ssh s1 "sudo nginx -t && systemctl is-active nginx && sudo tail -n 20 /var/log/nginx/error.log"
   ```

   失敗したら表示された行を直して再度commit・push・反映する
4. ベンチを回し、`make alp`・スコアを変更前と比較する。**複数の設定を1回のベンチでまとめて入れない**（どれが効いた/壊したか分からなくなる）。ただしbase-tuningの定番値のように、単体では差が出にくく壊れにくいものは1コミットにまとめてよい
5. 効果が無い・悪化したものは戻す（`git revert`）。結果をコミットメッセージかPRに「変更前→変更後（スコア・alpの該当行）」で残す

## 手順4: 最終盤（任意）

競技終了直前、これ以上計測しないと決めた段階でのみ、アクセスログを止めるとnginxのI/Oが減る。**以後`make alp`は使えなくなる**ので、チームで合意してから行う。

```nginx
access_log off;
```

再起動試験（サーバー再起動後も動くこと）を意識し、`systemctl is-enabled nginx`が`enabled`であることも確認する。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `sites-enabled/`のシンボリックリンクを編集して反映されない | 実体の`sites-available/`側を編集する。`ls -la`でリンクか確認する |
| `location`内で`proxy_set_header`を1つ足したら、`server`で定義していた`Host`等が消えた | `proxy_set_header`は1つでも書くと上位ブロックの定義を**全部継承しなくなる**。必要なヘッダを同じブロックに全部書く |
| upstreamに`keepalive`を書いたのに効かない | `proxy_http_version 1.1;`と`proxy_set_header Connection "";`をセットで入れる |
| 静的ファイルを返す`location`を足したらアプリの動的パス（例: `/image/:id`）まで404になった | alpで静的パスの実体を確認し、`try_files $uri @app;`でファイルが無ければアプリへ回す |
| `expires`でキャッシュさせたら整合性チェックで失格 | 更新され得るリソース（ユーザーのアイコン等）にキャッシュヘッダを付ける前に、マニュアルのキャッシュ規則を確認する（`isucon-score-strategy`の`docs/score-model.md`） |
| `open_file_cache_errors on`でアプリが後から書き出したファイルが404のまま | 動的に生成されるファイルを配るなら`open_file_cache_errors`は`off`（デフォルト）のままにする |
| ltsvの`log_format`/`access_log`を消して`make alp`が使えなくなった | 計測を止める合意（手順4）まではltsvの設定を残す |
| `nginx -t`を確認せずベンチを回して全滅 | 手順3-3を必ず行う |
