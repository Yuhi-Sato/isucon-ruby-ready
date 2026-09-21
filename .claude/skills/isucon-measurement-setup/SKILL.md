---
name: isucon-measurement-setup
description: ISUCONで初回ベンチマークを実行する前に必ず済ませる計測セットアップに使う。alpのmatching_groups、nginxのltsvログフォーマット、SQLクエリ位置コメントの問題適応まで。サービス名まわり（scripts/vars.shのSERVICE_NAME/APP_DIR/DB_SERVICE_NAME）は`isucon-service-name-setup`スキルが担当する。「ベンチを回せるようにして」「計測設定を入れて」「alpの設定をして」などのリクエストで使用する。
---

# ISUCON 計測セットアップ

## 概要
サービス名まわり（`SERVICE_NAME`/`APP_DIR`/`DB_SERVICE_NAME`）は`isucon-service-name-setup`スキルに委譲する。それ以外の各`references/`については、サブエージェントをそれぞれ起動してセットアップをしてください。

初回セットアップは`isucon-service-name-setup`スキル + 以下の`references/`全件が対象。`alp`の設定だけやり直したい等、一部だけやり直したい場合は該当するスキル・referenceだけ実施すればよい。

| リファレンス | 内容 |
|---|---|
| `isucon-service-name-setup`スキル | `scripts/vars.sh`の`SERVICE_NAME`/`APP_DIR`/`DB_SERVICE_NAME`を実サーバーの実装（Ruby/Go等の言語違いを含む）に合わせる |
| [alp-matching-setup.md](references/alp-matching-setup.md) | `tool-config/alp/config.yml`の`matching_groups`にルートの正規表現を設定し、`make alp`の集計をエンドポイント単位にまとめる |
| [nginx-ltsv-setup.md](references/nginx-ltsv-setup.md) | nginxのアクセスログをltsv形式にし、`make alp`が読める状態にする |
| [sql-location-comment-setup.md](references/sql-location-comment-setup.md) | mysql2のクエリ発行をprependし、SQL文に`/* file:line */`を埋め込んで`make slow-query`の結果からアプリのコードを直接特定できるようにする |
