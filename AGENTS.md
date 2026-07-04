# AGENTS.md

ISUCON競技当日にエージェントが使うコマンド一覧。詳細な手順・セットアップは `README.md` を参照。
`make help` で全ターゲットを一覧できる。

## 前提

- **エージェントはローカル1体に限定する。** サーバー上に常駐エージェントを起動しない（コンテキスト分断を避け、サーバーのワーキングツリーを誤って直接編集するリスクを避けるため）
- サーバー上のコマンドはローカルのエージェントから都度SSHで実行する（例: `ssh s1 "cd /home/isucon && make alp"`）。`make watch-service-log` など継続監視が必要なものはバックグラウンドSSHで実行する
- 都度SSHの接続確立コストを避けるため、`~/.ssh/config`にControlMaster/ControlPersistを設定しておく（[ローカルからのデプロイ](README.md#ローカルからのデプロイ手動フォールバック兼用)参照）
- サーバー上のコマンドは `/home/isucon`（リポジトリルート）で実行する
- `SERVICE_NAME` / `APP_DIR` などの変数は `Makefile` 冒頭で定義。問題に合わせて変更済みか最初に確認する
- `sh setup.sh`（`make setup` → `install-tools`）で `alp` / `notify_slack` / `pt-query-digest` は導入済み。エージェントが改めてインストールする必要はない

## 方針

- **改善方法は必ず計測結果（`make alp` / `make slow-query` / `make ns` / Vernierプロファイル等）に基づいて決める。** 推測だけでコードを変更しない

## スキル（`.agents/skills/`）

競技のフェーズに対応する作業手順書（スキル）を、クロスエージェント標準の配置である `.agents/skills/<名前>/SKILL.md` に用意している（[Agent Skills仕様](https://agentskills.io/specification)準拠）。
**該当フェーズの作業を始める前に必ず対応するSKILL.mdを読むこと。** スキル機構を持つエージェントは自動認識し、持たないエージェントも通常のMarkdownとして参照できる（`.claude/skills` は `.agents/skills` へのシンボリックリンク）。

| スキル | 使うタイミング |
|---|---|
| [isucon-initial-recon](.agents/skills/isucon-initial-recon/SKILL.md) | 競技開始直後の初動調査（レギュレーション確認〜ベースライン記録） |
| [isucon-bottleneck-analysis](.agents/skills/isucon-bottleneck-analysis/SKILL.md) | ベンチ後、計測結果から次の改善対象を決めるとき |
| [isucon-optimization-patterns](.agents/skills/isucon-optimization-patterns/SKILL.md) | アプリコードの改善（N+1・インデックス・キャッシュ等）を実装するとき |
| [isucon-mysql2-to-trilogy](.agents/skills/isucon-mysql2-to-trilogy/SKILL.md) | mysql2からtrilogyへのDBクライアント移行を検討・実施するとき |
| [isucon-server-tuning](.agents/skills/isucon-server-tuning/SKILL.md) | MySQL/nginx/アプリサーバー設定の変更や複数台構成への分割 |
| [isucon-final-check](.agents/skills/isucon-final-check/SKILL.md) | 終了約1時間前からの最終確認（ログ無効化・再起動試験・最終ベンチ） |

## 計測・解析（サーバー上で実行）

| コマンド | 用途 |
|---|---|
| `make alp` | nginxアクセスログ（ltsv）をalpで集計する |
| `make slow-query` | スロークエリログをpt-query-digestで集計する。N+1はCount列で検出する |
| `make ns` | alpとslow-queryの集計結果をまとめてSlackに通知する |
| `make extract-sql` | アプリの`.rb`からSQLを`queries/`以下に抽出する |
| `make watch-service-log` | アプリのsystemdログを追尾する |
| `make vernier-view` | 最新のVernierプロファイル（Markdown形式）を標準出力に表示する |

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
