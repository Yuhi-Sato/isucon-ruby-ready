# AGENTS.md

ISUCON競技当日にエージェントが使うコマンド一覧。詳細な手順・セットアップは `README.md` を参照。
`make help` で全ターゲットを一覧できる。

## 前提

- サーバー上のコマンドは `/home/isucon`（リポジトリルート）で実行する
- `SERVICE_NAME` / `APP_DIR` などの変数は `Makefile` 冒頭で定義。問題に合わせて変更済みか最初に確認する
- `sh setup.sh`（`make setup` → `install-tools`）で `alp` / `notify_slack` / `pt-query-digest` は導入済み。エージェントが改めてインストールする必要はない

## 方針

- **改善方法は必ず計測結果（`make alp` / `make slow-query` / `make ns` / Vernierプロファイル等）に基づいて決める。** 推測だけでコードを変更しない

## 計測・解析（サーバー上で実行）

| コマンド | 用途 |
|---|---|
| `make alp` | nginxアクセスログ（ltsv）をalpで集計する |
| `make slow-query` | スロークエリログをpt-query-digestで集計する。N+1はCount列で検出する |
| `make ns` | alpとslow-queryの集計結果をまとめてSlackに通知する |
| `make extract-sql` | アプリの`.rb`からSQLを`queries/`以下に抽出する |
| `make watch-service-log` | アプリのsystemdログを追尾する |
| `make vernier-view` | 最新のVernierプロファイルをビューアで開く |

## デプロイ・ベンチ

| コマンド | 実行場所 | 用途 |
|---|---|---|
| `make bench` | サーバー | **ベンチ実行直前のみ。** ログ消去・設定反映・DB/nginx含む全再起動を伴う |
| `make deploy` | サーバー | 軽量デプロイ（mainマージ時はCIが自動実行）。ログは消えない |
| `make remote-deploy-s1` | ローカル | 対象サーバーだけデプロイ（`-s2` / `-s3` も同様） |
| `make remote-deploy-all` | ローカル | 全サーバーへ並列デプロイ |

## 設定ファイルの取得・反映（サーバー上で実行）

| コマンド | 用途 |
|---|---|
| `make get-conf` | サーバーの実際のDB/nginx設定を`s1/`等のgit管理下にコピーする |
| `make deploy-conf` | git管理下の設定をサーバーに反映する（`make bench`に含まれる） |
| `make restart` | DB→アプリ→nginxの順に全再起動する |
| `make restart-app` | アプリのみ再起動する |

## 禁止・注意事項

- **`make bench` を計測中に叩かない。** ログが消えてDB/nginxが再起動する。他メンバーの計測を破壊する
- **`make add-profiling-gems` はローカル専用。** サーバーで実行するとGemfile.lockが変更され、以後の `git pull` がconflictで失敗する
- サーバーのワーキングツリーを直接編集しない。変更はローカル→push→デプロイの流れで反映する
- `make bench` / `make deploy` 以外でログを消さない（`make rm-logs` 単体は原則使わない）
