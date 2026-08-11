---
name: isucon-measurement-setup
description: ISUCONで初回ベンチマークを実行する前に必ず済ませる計測セットアップに使う。scripts/vars.shの変数（SERVICE_NAME/APP_DIR/DB_SERVICE_NAME）、alpのmatching_groups、nginxのltsvログフォーマット、ユーザー行動履歴ロガーの問題適応まで。「ベンチを回せるようにして」「計測設定を入れて」「alpの設定をして」などのリクエストで使用する。
---

# ISUCON 計測セットアップ

## 概要
各`references/`について、サブエージェントをそれぞれ起動してセットアップをしてください。
