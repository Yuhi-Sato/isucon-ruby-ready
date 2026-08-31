---
name: isucon-measurement-setup
description: ISUCONで初回ベンチマークを実行する前に必ず済ませる計測セットアップに使う。scripts/vars.shの変数（SERVICE_NAME/APP_DIR/DB_SERVICE_NAME）、alpのmatching_groups、nginxのltsvログフォーマット、SQLクエリ位置コメント、ユーザー行動履歴ロガーの問題適応まで。「ベンチを回せるようにして」「計測設定を入れて」「alpの設定をして」などのリクエストで使用する。
---

# ISUCON 計測セットアップ

## 概要
各`references/`について、サブエージェントをそれぞれ起動してセットアップをしてください。

初回セットアップは全件対象。`alp`の設定だけやり直したい等、一部だけやり直したい場合は該当する`references/`だけ読んで実施すればよい。

| リファレンス | 内容 |
|---|---|
| [service-name-setup.md](references/service-name-setup.md) | `scripts/vars.sh`の`SERVICE_NAME`/`APP_DIR`/`DB_SERVICE_NAME`を実サーバーの実装（Ruby/Go等の言語違いを含む）に合わせる |
| [alp-matching-setup.md](references/alp-matching-setup.md) | `tool-config/alp/config.yml`の`matching_groups`にルートの正規表現を設定し、`make alp`の集計をエンドポイント単位にまとめる |
| [nginx-ltsv-setup.md](references/nginx-ltsv-setup.md) | nginxのアクセスログをltsv形式にし、`make alp`が読める状態にする |
| [sql-location-comment-setup.md](references/sql-location-comment-setup.md) | mysql2のクエリ発行をprependし、SQL文に`/* file:line */`を埋め込んで`make slow-query`の結果からアプリのコードを直接特定できるようにする |

ユーザー行動履歴ロガー（`X-User-Id`ヘッダー・nginxの`userid`フィールド）の導入は`isucon-user-behavior-analysis`スキルの「1. 当日の導入手順」を参照。計測セットアップの一部として同じタイミングで実施する。
