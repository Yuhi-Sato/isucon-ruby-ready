---
name: isucon-initial-recon
description: ISUCON競技開始直後の初動調査で使う。レギュレーション確認、問題アプリの構造把握、DBスキーマ・インデックス調査、vars.sh変数・alp設定の問題適応、ベースラインスコア記録まで。「初動調査して」「問題を把握して」「まず何をすればいい？」などのリクエストで使用する。
---

# ISUCON 初動調査

## 概要

競技開始から最初のベンチまでに「どこで点が入り、どこが遅そうか」の地図を作る。
ここで作った地図が以降の全改善の土台になる。**改善はまだしない。調査に徹する。**

調査は独立した3トラックに分かれており、サブエージェント（Agentツール等）で**並列実行**できる。

## 実行モデル

```
トラックA: レギュレーション読解 ──┐
トラックB: サーバー調査（SSH）  ──┼─→ 統合フェーズ ─→ ベースライン計測
トラックC: アプリ調査（ローカル）──┘   （設定反映）      （make bench-prep）
```

- トラックA〜Cは互いに依存しない。**同時に開始してよい**
- 統合フェーズは**3トラックの結果が揃ってから**（Bのサービス名・Cのルート一覧とセッションキーを使う）
- ベースラインは**統合フェーズ完了後**（alp設定・ロガー・vars.sh変数が反映されていないベンチはやり直しになる）

### 並列実行のルール

- サブエージェントは**調査（読み取り）専用**にする。ファイル編集や `docs/recon.md` への書き込みはさせず、調査結果をテキストで返させて、メインエージェントが `docs/recon.md` に統合する（並列書き込みでメモが消えるのを防ぐ）。例外はトラックCの `make extract-sql`（`queries/` を生成するが他トラックと衝突しない）
- サーバーへの並列SSHは問題ない（ControlMasterで接続が多重化される）。CLAUDE.mdの「エージェントはローカル1体」は**サーバー上に常駐させない**という意味で、ローカルのサブエージェント並列は妨げない

## トラックA: レギュレーション・当日マニュアル（最優先）

以下を必ず抜き出してメモする:

- **スコア計算式**（成功リクエストの重み、減点条件）
- **失格条件**（レスポンス内容の変更禁止範囲、DNS/IP制約など）
- **再起動試験の有無**（あるなら isucon-final-check スキルで再起動試験が必須になる）
- ベンチマークの整合性チェック内容（キャッシュ可能性の判断材料になる）

マニュアルがポータル上にしかなくエージェントが読めない場合は、人間に本文の貼り付けかMarkdown化を依頼する。

## トラックB: サーバー調査（SSH・読み取り専用）

### B-1. 実サービス名の特定

```bash
systemctl list-units --type=service | grep -iE 'isu|ruby|mysql|maria|nginx'
```

`SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME`（`scripts/vars.sh` の変数）に設定すべき値を特定して報告する。修正自体は統合フェーズで行う。

### B-2. DBスキーマ・データ量

```bash
sudo mysql -e "SHOW DATABASES;"
sudo mysql <db> -e "SHOW TABLES;"
sudo mysql <db> -e "SHOW CREATE TABLE <table>\G"   # インデックス有無を確認
sudo mysql <db> -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = '<db>' ORDER BY table_rows DESC;"
```

メモする内容: テーブル一覧・行数・**インデックスが無いテーブル**・BLOB/TEXTカラム（画像がDBに入っていれば静的配信化の候補）。

### B-3. 計測まわりのDB設定確認

```bash
sudo mysql -e "SELECT @@performance_schema;"   # make slow-query の計測ソース。1ならOK
```

- `0` の場合（MariaDB出題など）: 統合フェーズで `make get-conf` 後に `sN/etc/mysql/` へ `performance_schema = ON` を追加して反映する。有効化できない場合は従来方式（`long_query_time = 0` でslow logを有効化し `sudo pt-query-digest /var/log/mysql/mysql-slow.log`）にフォールバックする（isucon-mysql-tuning スキル参照）
- `slow_query_log` は**常時OFF運用**（計測はperformance_schemaで行うためスロークエリログは不要。I/O削減でスコアにも効く）。統合フェーズで `sN/etc/mysql/` へ `slow_query_log = 0` を明示しておく

## トラックC: アプリ調査（ローカルリポジトリ）

```bash
# ルート一覧（Sinatra想定）
grep -nE "^\s*(get|post|put|delete|patch) " webapp/ruby/*.rb

# SQLを queries/ 以下に抽出
make extract-sql
```

- エンドポイントごとに「何をするか」を1行でメモする
- 初期化エンドポイント（`POST /initialize` 等）の中身を読む。**DBを再構築する場合、後で追加するインデックスはここに仕込む必要がある**（isucon-optimization-patterns スキル参照）
- **セッションのユーザーIDキーを特定する**（統合フェーズの行動履歴ロガー導入で使う）

## 統合フェーズ（3トラック完了後）

以下の3つは**触るファイルが互いに異なるため、これも並列化できる**。編集はすべてローカル→push→サーバーで反映（サーバーのワーキングツリーは直接編集しない）。

1. **`scripts/vars.sh` の変数修正**（←トラックB-1）: `SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME` を実サービス名に合わせる。READMEの「当日チェックリスト」（alp設定・nginx ltsvフォーマット・Slack Webhook）も済んでいるか確認する
2. **alpのmatching_groups**（←トラックC）: ルート一覧をもとに `tool-config/alp/config.yml` の `matching_groups` を編集する。可変部分（`:id` 等）を正規表現でまとめないと、alpの集計がURLごとにバラけて使いものにならない
3. **ユーザー行動履歴ロガー**（←トラックC）: isucon-user-behavior-analysis スキルの導入手順に従い、Rackミドルウェア（`X-User-Id`ヘッダー付与）とnginxの`proxy_hide_header`を入れる。トラックCで特定したセッションのユーザーIDキーを使う。ここで入れておくと、ベースラインを含む**以降すべてのベンチで行動履歴が自動的に手に入る**。後から入れると、欲しくなった瞬間のベンチデータにはuseridが無い

あわせてトラックB-3で必要になったMySQL設定（`performance_schema = ON` / `slow_query_log = 0`）を `sN/etc/mysql/` に反映し、全トラックの調査結果を `docs/recon.md` に統合する（書き込みはメインエージェントのみ）。

## ベースライン記録（統合フェーズ完了後）

```bash
make bench-prep          # サーバー上で実行するベンチの「準備」（ログ消去・設定反映・全再起動）
# → ベンチマーカー本体はポータル等から実行し、初回スコアを docs/recon.md に記録
make alp            # ベンチ後すぐ集計
make slow-query
```

初回の `make alp` / `make slow-query` の上位結果もメモに貼る。これが最初の改善対象になる（解釈は isucon-bottleneck-analysis スキル）。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| レギュレーションを読まずに改善を始め、失格条件を踏む | トラックAを必ず最初に開始する（他トラックと並列でよいが、統合前に完了させる） |
| `SERVICE_NAME` が違うまま `make bench-prep` して古いアプリを計測する | トラックB-1で実サービス名を確認し、統合フェーズで修正してからベンチする |
| matching_groups未設定でalpの結果がURLごとに分散する | 統合フェーズをベンチ前に済ませる |
| 統合フェーズ完了前にベースラインベンチを実行する | alp設定・ロガー・vars.sh変数なしのベンチはやり直しになる。バリアを守る |
| サブエージェントが並列で `docs/recon.md` を編集し内容が消える | 書き込みはメインエージェントのみ。サブエージェントは結果をテキストで返す |
| 調査中に「ついでに」コードを直し始める | 初動では改善しない。改善は計測結果を見てから |
