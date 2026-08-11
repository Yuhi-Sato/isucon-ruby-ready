---
name: isucon-initial-recon
description: ISUCON競技開始直後の初動調査で使う。レギュレーション確認、問題アプリの構造・ルート一覧の把握、DBスキーマ・インデックス調査、実サービス名の特定まで。計測設定の反映とベースライン計測は isucon-measurement-setup スキルに委譲する。「初動調査して」「問題を把握して」「まず何をすればいい？」などのリクエストで使用する。
---

# ISUCON 初動調査

## 概要

競技開始から最初のベンチまでに「どこで点が入り、どこが遅そうか」の地図を作る。
ここで作った地図が以降の全改善の土台になる。**改善はまだしない。調査に徹する。**

調査は独立した3トラックに分かれており、サブエージェント（Agentツール等）で**並列実行**できる。

## 実行モデル

```
トラックA: レギュレーション読解 ──┐
トラックB: サーバー調査（SSH）  ──┼─→ docs/recon.md に統合 ─→ isucon-measurement-setup スキルへ
トラックC: アプリ調査（ローカル）──┘                            （計測セットアップ → ベースライン計測）
```

- トラックA〜Cは互いに依存しない。**同時に開始してよい**
- **調査が終わってもベンチはまだ実行しない。** 計測設定（vars.sh変数・alp・nginx ltsv・performance_schema・行動履歴ロガー）を反映していないベンチはやり直しになる。isucon-measurement-setup スキルに進むこと
- トラックB-1・トラックCの結果は、そのまま isucon-measurement-setup スキルへの入力になる

### 並列実行のルール

- サブエージェントは**調査（読み取り）専用**にする。ファイル編集や `docs/recon.md` への書き込みはさせず、調査結果をテキストで返させて、メインエージェントが `docs/recon.md` に統合する（並列書き込みでメモが消えるのを防ぐ）
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

`SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME`（`scripts/vars.sh` の変数）に設定すべき値を特定して報告する。
**ここでは値を特定するだけで、修正はしない。** 反映は isucon-measurement-setup スキルで行う。

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

`0`だった場合（MariaDB出題など）はその事実を報告する。設定の反映は isucon-measurement-setup スキルで行う。

## トラックC: アプリ調査（ローカルリポジトリ）

```bash
# ルート一覧（Sinatra想定）
grep -nE "^\s*(get|post|put|delete|patch) " webapp/ruby/*.rb
```

- エンドポイントごとに「何をするか」を1行でメモする
- 初期化エンドポイント（`POST /initialize` 等）の中身を読む。**DBを再構築する場合、後で追加するインデックスはここに仕込む必要がある**（isucon-optimization-patterns スキル参照）
- **セッションのユーザーIDキーを特定する**

このうち**ルート一覧**（alpのmatching_groups用）と**セッションのユーザーIDキー**（行動履歴ロガー用）は、
isucon-measurement-setup スキルへの入力になるので、`docs/recon.md` に必ず残す。

## 調査結果のまとめ

全トラックの結果は `docs/recon.md` に統合する（書き込みはメインエージェントのみ）。
まとまったら isucon-measurement-setup スキルに進み、計測セットアップとベースライン計測を行う。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| レギュレーションを読まずに改善を始め、失格条件を踏む | トラックAを必ず最初に開始する（他トラックと並列でよい） |
| 調査が終わった勢いでそのままベンチを実行してしまう | 計測セットアップ（isucon-measurement-setup スキル）を挟む。設定なしのベンチはやり直しになる |
| サブエージェントが並列で `docs/recon.md` を編集し内容が消える | 書き込みはメインエージェントのみ。サブエージェントは結果をテキストで返す |
| 調査中に「ついでに」コードを直し始める | 初動では改善しない。改善は計測結果を見てから |
