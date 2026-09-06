推測するな。計測せよ。

ロジックはアプリケーション層に寄せて書いてください。
人間の認知負荷がかかるため、インフラにロジックは書かない。
ロジックの変更が終了後テストを実行し、異常がないかを確認してください。

## ISUCON Skills の実行順序

競技中は以下の順序でスキルを使うのが基本。ただし異常発生時は適宜 `isucon-troubleshooting` を挟む。

1. `isucon-initial-recon`: 問題の把握、サービス名・ルート・DBスキーマ・インデックスの確認
2. `isucon-measurement-setup`: 計測環境のセットアップ（alp, slow-query, ユーザー行動履歴）
3. `isucon-ruby-testing`: リファクタ前に回帰テストを作成（推奨）
4. ベンチマーク実行
5. `isucon-bottleneck-analysis`: 計測結果からボトルネックを1つ特定
6. `isucon-vernier-profiling` / `isucon-newrelic-setup`: 必要に応じて詳細プロファイリング
7. `isucon-user-behavior-analysis`: 必要に応じてユーザー行動履歴を分析
8. `isucon-optimization-patterns`: 特定したボトルネックを解消
9. 4-8 を繰り返し、スコアが頭打ちになったら `isucon-final-check` に移る
10. `isucon-final-check`: 競技終了前の最終確認（計測無効化・再起動試験・最終ベンチ）

各スキルは単独でも呼べるが、計測なしの最適化は避け、必ず `isucon-measurement-setup` → ベンチ → `isucon-bottleneck-analysis` のサイクルを回してから `isucon-optimization-patterns` を使う。
