# 役割分担表

担当者名は競技開始時に埋める。

## メンバー

GitHubでこのリポジトリにコミットしているアカウント（Claude・Cursorなどのbotは除く）。

| GitHubアカウント | コミット数 |
| --- | --- |
| [Yuhi-Sato](https://github.com/Yuhi-Sato) | 160 |
| [garebareDA](https://github.com/garebareDA) | 24 |
| [u-ktk](https://github.com/u-ktk) | 6 |

コミット数は`gh api repos/:owner/:repo/contributors`の値（作成時点）。

| 役割 | 担当者 | 主な担当範囲 | 参照スキル |
| --- | --- | --- | --- |
| 計測・分析担当 | | ベンチ実行、alp / slow-query / Vernierの結果解釈、次の改善対象の決定 | `isucon-bottleneck-analysis` / `isucon-vernier-profiling` |
| アプリ改善担当 | | N+1解消、キャッシュ、bulk insertなどRubyコードの改善 | `isucon-optimization-patterns` |
| DB・インフラ担当 | | インデックス追加、MySQL / nginx設定、サーバー間の構成 | `isucon-optimization-patterns` |
| テスト・検証担当 | | 回帰テスト、ベンチFAIL時の切り分け、再起動試験 | `isucon-ruby-testing` / `isucon-troubleshooting` / `isucon-final-check` |

## 時間帯ごとの動き

| 時間帯 | 全員 | 補足 |
| --- | --- | --- |
| 開始〜初回ベンチ | 環境セットアップ、計測設定 | `isucon-measurement-setup` |
| 中盤 | 計測→改善→デプロイのサイクル | 1サイクルで直す対象は1つ |
| 終了1時間前〜 | 計測用ログ・プロファイラの無効化、最終確認 | `isucon-final-check` |

## 引き継ぎメモ

- 
