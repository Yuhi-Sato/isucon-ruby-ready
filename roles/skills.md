# メンバー別の必要スキル

各メンバーが使いそうなスキル（`.claude/skills/`）とコマンド（`.claude/commands/`）のメモ。担当は`initial-steps.md`と`after-initial.md`に基づく。

## Yuhi-Sato

| 時期 | スキル / コマンド | 用途 |
| --- | --- | --- |
| 初動 | `isucon-ruby-testing` | リファクタ前の回帰テスト環境を作る |
| 初動 | `/update-architecture-diagram` | サーバ構成・通信経路の図をmermaidで描く |
| 初動以降 | `branch-pr-workflow` | ブランチを切り、ベンチ前にサーバーへ反映する |
| 初動以降 | `issue-sync` | 着手前に、割り当てられたissueがあり競合が無いか確認する |
| 初動以降 | `create-pr` | PRを作成する |
| 初動以降 | `isucon-mysql-config-tuning` | MySQL設定の最適化（issueになった場合） |
| 初動以降 | `isucon-nginx-tuning` | nginx設定の最適化（issueになった場合） |

## u-ktk

| 時期 | スキル / コマンド | 用途 |
| --- | --- | --- |
| 初動 | `/update-isucon-spec` | マニュアルから出題仕様の辞書（`isucon-spec`）を作る |
| 初動以降 | `isucon-spec` | ルール・ベンチ判定・アプリ仕様を確認する |
| 初動以降 | `isucon-score-strategy` | ベンチ結果とスコア規則から次の一手を決める |
| 初動以降 | `issue-sync` | 分析結果をissueに起票し、スコア確認後にクローズする |

## garebareDA

| 時期 | スキル / コマンド | 用途 |
| --- | --- | --- |
| 初動 | `isucon-service-name-setup` | `scripts/vars.sh`を実サーバーに合わせる（最優先） |
| 初動 | `isucon-measurement-setup` | alp・nginxのltsvログ・SQLコメントなど計測設定を入れる |
| 初動以降 | `branch-pr-workflow` | ブランチを切り、ベンチ前にサーバーへ反映する |
| 初動以降 | `issue-sync` | 着手前に、割り当てられたissueがあり競合が無いか確認する |
| 初動以降 | `create-pr` | PRを作成する |
| 初動以降 | `isucon-mysql-config-tuning` | MySQL設定の最適化（issueになった場合） |
| 初動以降 | `isucon-nginx-tuning` | nginx設定の最適化（issueになった場合） |

## メモ

- Yuhi-SatoとgarebareDAは初動以降の役割が同じなので、PR作成まわりのスキルは共通
