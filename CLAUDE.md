# CLAUDE.md

ISUCON競技当日にエージェントが使うコマンド一覧。詳細な手順・セットアップは `README.md` を参照。
`make help` で全ターゲットを一覧できる。

## 前提

- **エージェントはローカル1体に限定する。** サーバー上に常駐エージェントを起動しない（コンテキスト分断を避け、サーバーのワーキングツリーを誤って直接編集するリスクを避けるため）
- サーバー上のコマンドはローカルのエージェントから都度SSHで実行する（例: `ssh s1 "cd /home/isucon && make alp"`）。`make watch-service-log` など継続監視が必要なものはバックグラウンドSSHで実行する
- SSH接続の設定（ControlMaster/ControlPersistによる接続の使い回し、GitHub認証用のForwardAgent）は`setup.sh`が`~/.ssh/config`に自動生成済み（[SSH接続の設定](README.md#ssh接続の設定)参照）
- サーバー上のコマンドは `/home/isucon`（リポジトリルート）で実行する
- `SERVICE_NAME` / `APP_DIR` などの変数は `scripts/vars.sh` で定義。問題に合わせて変更済みか最初に確認する。Makefileはショートカット集で、ロジックは `scripts/` 以下のシェルスクリプトにある
- `./setup.sh`（内部で `remote-setup.sh` → `sh server-setup.sh <s1|s2|s3>` → `make setup` → `install-tools`）で `alp` / `notify_slack` / `pt-query-digest` は導入済み。エージェントが改めてインストールする必要はない

## 方針

- **改善方法は必ず計測結果（`make alp` / `make slow-query` / `make ns` / Vernierプロファイル等）に基づいて決める。** 推測だけでコードを変更しない

## スキル（`.claude/skills/`）

競技のフェーズに対応する作業手順書（スキル）を `.claude/skills/<名前>/SKILL.md` に用意している。
**該当フェーズの作業を始める前に必ず対応するSKILL.mdを読むこと。**

| スキル | 使うタイミング |
|---|---|
| [isucon-initial-recon](.claude/skills/isucon-initial-recon/SKILL.md) | 競技開始直後の初動調査（レギュレーション確認・アプリ構造把握・DBスキーマ調査・実サービス名の特定） |
| [isucon-measurement-setup](.claude/skills/isucon-measurement-setup/SKILL.md) | 初回ベンチの前に計測基盤（`scripts/vars.sh`変数・alp・nginx ltsv・performance_schema・行動履歴ロガー）を問題に合わせるとき。ベースライン計測まで |
| [isucon-bottleneck-analysis](.claude/skills/isucon-bottleneck-analysis/SKILL.md) | ベンチ後、計測結果から次の改善対象を決めるとき |
| [isucon-optimization-patterns](.claude/skills/isucon-optimization-patterns/SKILL.md) | アプリコードの改善（N+1・インデックス・キャッシュ等）を実装するとき |
| [isucon-mysql2-to-trilogy](.claude/skills/isucon-mysql2-to-trilogy/SKILL.md) | mysql2からtrilogyへのDBクライアント移行を検討・実施するとき |
| [isucon-vernier-profiling](.claude/skills/isucon-vernier-profiling/SKILL.md) | Vernierの導入・実行・プロファイルの読み方 |
| [isucon-ruby-runtime-tuning](.claude/skills/isucon-ruby-runtime-tuning/SKILL.md) | YJIT有効化・GC設定などコード変更なしのRubyランタイムチューニング |
| [isucon-puma-tuning](.claude/skills/isucon-puma-tuning/SKILL.md) | Pumaのworkers/threads構成を調整するとき |
| [isucon-nginx-caching](.claude/skills/isucon-nginx-caching/SKILL.md) | nginxのHTTPキャッシュ（proxy_cache）でアプリへのリクエストを減らすとき |
| [isucon-user-behavior-analysis](.claude/skills/isucon-user-behavior-analysis/SKILL.md) | ユーザー行動履歴（userid付きアクセスログ）の記録導入と、DuckDBでの行動フロー・リピート分析 |
| [isucon-mysql-tuning](.claude/skills/isucon-mysql-tuning/SKILL.md) | MySQL設定（my.cnf）のチューニング（I/O・buffer pool・接続数等） |
| [isucon-nginx-tuning](.claude/skills/isucon-nginx-tuning/SKILL.md) | nginx設定のチューニング（keepalive・静的配信・UNIXソケット等） |
| [isucon-server-tuning](.claude/skills/isucon-server-tuning/SKILL.md) | 複数台構成への分割（DB分離・アプリ複数台）やsystemdユニットの調整 |
| [isucon-troubleshooting](.claude/skills/isucon-troubleshooting/SKILL.md) | ベンチFAIL・整合性エラー・アプリ起動しない・スコア急落などの障害対応 |
| [isucon-final-check](.claude/skills/isucon-final-check/SKILL.md) | 終了約1時間前からの最終確認（ログ無効化・再起動試験・最終ベンチ） |

## 計測・解析（サーバー上で実行）

| コマンド | 用途 |
|---|---|
| `make alp` | nginxアクセスログ（ltsv）をalpで集計する |
| `make slow-query` | performance_schemaのクエリダイジェスト集計を表示する。N+1はcalls列で検出する |
| `make duckdb-<レシピ>` | ユーザー行動履歴の定型分析（`duckdb-flow` / `duckdb-repeat` / `duckdb-heavy-users`） |
| `make ns` | alpとslow-queryの集計結果をまとめてSlackに通知する |
| `make watch-service-log` | アプリのsystemdログを追尾する |
| `make journal-errors` | systemdログからwarning/errorレベルのログだけを抽出する（`SINCE=-10min` 等で範囲を絞る） |
| `make vernier-view` | 最新のVernierプロファイル（Markdown形式）を標準出力に表示する |

## デプロイ・ベンチ

| コマンド | 実行場所 | 用途 |
|---|---|---|
| `make bench-prep` | サーバー | **ベンチ実行直前のみ。** ログ消去・設定反映・DB/nginx含む全再起動を伴う |
| `make deploy` | サーバー | 軽量デプロイ（手動実行）。ログは消えない |
| `make remote-deploy-s1` | ローカル | 対象サーバーだけデプロイ（`-s2` / `-s3` も同様） |
| `make remote-deploy-all` | ローカル | 全サーバーへ並列デプロイ |

## 設定ファイルの取得・反映（サーバー上で実行）

| コマンド | 用途 |
|---|---|
| `make get-conf` | サーバーの実際のDB/nginx設定を`s1/`等のgit管理下にコピーする |
| `make deploy-conf` | git管理下の設定をサーバーに反映する（`make bench-prep`に含まれる） |
| `make restart` | DB→アプリ→nginxの順に全再起動する |
| `make restart-app` | アプリのみ再起動する |

## 禁止・注意事項

- **`make bench-prep` を計測中に叩かない。** ログが消えてDB/nginxが再起動する。他メンバーの計測を破壊する
- **`make add-profiling-gems` はローカル専用。** サーバーで実行するとGemfile.lockが変更され、以後の `git pull` がconflictで失敗する
- サーバーのワーキングツリーを直接編集しない。変更はローカル→push→デプロイの流れで反映する
- サーバー上のgitはローカルから転送されたssh-agent（ForwardAgent）でGitHubに認証する。サーバー単体（cron等、転送なしのセッション）では `git pull` が失敗する
- `make bench-prep` / `make deploy` 以外でログを消さない（`make rm-logs` 単体は原則使わない）
