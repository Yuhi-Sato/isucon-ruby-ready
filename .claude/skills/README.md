# ISUCON Skills

このディレクトリは ISUCON 競技で使う Claude スキルをまとめたもの。
各スキルは単独で呼び出せるが、以下の実行順序を基本とする。

## Skills 一覧

| スキル名 | 用途 |
| --- | --- |
| `isucon-bottleneck-analysis` | ベンチ実行後の計測結果を解釈し、次の改善対象を1つ決める |
| `isucon-final-check` | 競技終了の約1時間前から最終提出までの最終確認 |
| `isucon-measurement-setup` | 初回ベンチマーク実行前の計測セットアップ |
| `isucon-newrelic-setup` | New Relic Ruby Agent の導入と計測有効化 |
| `isucon-optimization-patterns` | ボトルネック特定後のアプリコード改善 |
| `isucon-ruby-testing` | リファクタ前の Docker + minitest/rack-test による回帰テスト作成 |
| `isucon-troubleshooting` | ベンチ FAIL・502・スコア急落などの異常対応 |
| `isucon-user-behavior-analysis` | ユーザー行動履歴の記録と DuckDB による分析 |
| `isucon-vernier-profiling` | Vernier サンプリングプロファイラの導入・実行 |

## 実行順序

競技中は以下の順序でスキルを使うのが基本。異常発生時は適宜 `isucon-troubleshooting` を挟む。

1. `isucon-initial-recon`（`.agents/skills` に配置）: 問題の把握、サービス名・ルート・DBスキーマ・インデックスの確認
2. `isucon-measurement-setup`: 計測環境のセットアップ（alp, slow-query, ユーザー行動履歴）
3. `isucon-ruby-testing`: リファクタ前に回帰テストを作成（推奨）
4. ベンチマーク実行
5. `isucon-bottleneck-analysis`: 計測結果からボトルネックを1つ特定
6. `isucon-vernier-profiling` / `isucon-newrelic-setup`: 必要に応じて詳細プロファイリング
7. `isucon-user-behavior-analysis`: 必要に応じてユーザー行動履歴を分析
8. `isucon-optimization-patterns`: 特定したボトルネックを解消
9. 4-8 を繰り返し、スコアが頭打ちになったら `isucon-final-check` に移る
10. `isucon-final-check`: 競技終了前の最終確認（計測無効化・再起動試験・最終ベンチ）

## 注意

- **計測なしの最適化は避ける**。必ず `isucon-measurement-setup` → ベンチ → `isucon-bottleneck-analysis` のサイクルを回してから `isucon-optimization-patterns` を使う。
- `isucon-ruby-testing` はテスト作成・実行のみを担当し、N+1解消・インデックス追加・リファクタなどは `isucon-optimization-patterns` 等に委譲する。
- `isucon-newrelic-setup` は APM 計測を一時的に有効化したいときに使い、最終ベンチの性能測定だけを目的とする場合は使わない。
