---
name: isucon-spec
description: 出題仕様の辞書。競技のルール、ベンチの判定（スコア計算式・エラーコード・タイムアウト等）、アプリの仕様を、ログ・DB・ベンチのソースの語で収める。施策の仮説や作戦を立てる前、ベンチのログの数値の意味を書く前、スコアが上がらない理由を説明する前に、推測せず必ず読む。中身は競技ごとに`/update-isucon-spec`で作る。
---

# 出題仕様の辞書

マニュアルの語を、ログ・DB・ベンチのソースの語に引き直した辞書。語はソースの文字列そのままなので、見つけた語でそのまま検索できる。（未確認）は確認できていない内容。

まだ内容が無い場合は `/update-isucon-spec` でマニュアルから作る。書式・作り方は [update-isucon-spec](../../commands/update-isucon-spec.md) を参照。記入例は [references/isucon14-example.md](references/isucon14-example.md)（ISUCON14を実際に埋めたもの）。

実ログの置き場は `docs/bench/`（`make save-bench-log` で保存する）。

<!-- 以降、/update-isucon-spec が競技ごとに書き足す。マニュアルの `##` を見出しにする。 -->
