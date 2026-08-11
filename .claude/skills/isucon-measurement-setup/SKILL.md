---
name: isucon-measurement-setup
description: ISUCONで初回ベンチマークを実行する前に必ず済ませる計測セットアップに使う。scripts/vars.shの変数（SERVICE_NAME/APP_DIR/DB_SERVICE_NAME）、alpのmatching_groups、nginxのltsvログフォーマット、MySQLのperformance_schema、ユーザー行動履歴ロガーの問題適応と、ベースライン計測まで。「ベンチを回せるようにして」「計測設定を入れて」「alpの設定をして」「ベースラインを取って」などのリクエストで使用する。
---

# ISUCON 計測セットアップ

## 概要

初回ベンチマークを回す前に、計測基盤を問題に合わせる。ここが未完了のままベンチを実行すると、
**古いアプリを計測する・alpの集計がバラける・slow-queryが空になる・行動履歴にuseridが無い**といった形で
計測データが使いものにならず、ベンチをやり直すことになる。**ベンチ実行はここが全部終わってから。**

この5項目は「やらないとベンチがやり直しになる」ブロッキングな作業であり、問題把握のための調査（isucon-initial-recon スキル）とは別物。
調査は後からでも取り返せるが、ベンチデータは後から取り返せない。

各項目は手順が長いため、詳細は `references/` 以下の個別ファイルに分けている。このSKILL.md自体は全体像と参照先の案内に徹する。

## 前提入力

isucon-initial-recon スキルの調査結果から、以下3つを受け取る。

| 入力 | 出どころ | 使う項目 |
|---|---|---|
| 実サービス名（`SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME`） | トラックB-1 | 1 |
| ルート一覧（可変部分を持つパス） | トラックC | 2 |
| セッションのユーザーIDキー | トラックC | 5 |

初動調査を経ずにこのスキル単体で始めてもよい。各 `references/` の手順1に、必要な値を自分で調べるコマンドが入っている。

## セットアップ項目（5つ・並列可）

**触るファイルが互いに異なるため、5項目は並列に進められる。** 編集はすべてローカル→push→サーバーで反映する
（サーバーのワーキングツリーは直接編集しない）。各項目の詳細手順は対応する `references/` ファイルを読んでから行う。

1. **scripts/vars.sh の変数修正**: [references/service-name-setup.md](references/service-name-setup.md) — `SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME` を実サービス名に合わせる
2. **alpのmatching_groups**: [references/alp-matching-setup.md](references/alp-matching-setup.md) — ルート一覧をもとに `tool-config/alp/config.yml` を設定する
3. **nginxのltsvログフォーマット**: [references/nginx-ltsv-setup.md](references/nginx-ltsv-setup.md) — `make alp` が読めるログ形式にする
4. **MySQLの計測設定**: [references/mysql-measurement-setup.md](references/mysql-measurement-setup.md) — `performance_schema` / `slow_query_log` の設定を反映する
5. **ユーザー行動履歴ロガー**: isucon-user-behavior-analysis スキルの導入手順に従い、Rackミドルウェア（`X-User-Id`ヘッダー付与）とnginxの`proxy_hide_header`を入れる（3のltsvセットアップとあわせて行う）。トラックCで特定したセッションのユーザーIDキーを使う。ここで入れておくと、ベースラインを含む**以降すべてのベンチで行動履歴が自動的に手に入る**。後から入れると、欲しくなった瞬間のベンチデータにはuseridが無い

あわせて `tool-config/alp/notify-slack.toml.example` / `tool-config/slow-query/notify-slack.toml.example` をコピーしてWebhook URLを設定する（`make ns` で結果をSlackに流せるようになる）。

## ベースライン記録（5項目完了後）

```bash
make bench-prep     # サーバー上で実行するベンチの「準備」（ログ消去・設定反映・全再起動）
# → ベンチマーカー本体はポータル等から実行し、初回スコアを docs/recon.md に記録
make alp            # ベンチ後すぐ集計
make slow-query
```

初回の `make alp` / `make slow-query` の上位結果もメモに貼る。ここで
**alpの行がURLパターン単位に集約されているか・slow-queryが空でないか**を確認すれば、5項目の反映が効いていることの検証にもなる。
これが最初の改善対象になる（解釈は isucon-bottleneck-analysis スキル）。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `SERVICE_NAME` が違うまま `make bench-prep` して古いアプリを計測する | 項目1を最優先で済ませる。`systemctl list-units` の実サービス名と突き合わせる |
| matching_groups未設定でalpの結果がURLごとに分散する | 項目2をベンチ前に済ませる |
| 5項目の完了前にベースラインベンチを実行する | alp設定・ロガー・vars.sh変数なしのベンチはやり直しになる。バリアを守る |
| 行動履歴ロガーを後から入れて、ベースラインのベンチデータにuseridが無い | 項目5をベースライン前に入れる。ベンチデータは後から取り返せない |
| ローカルで直しただけでpushしておらず、サーバーに反映されない | サーバーは`origin/main`から取得する。commit・push してから `make bench-prep` する |
