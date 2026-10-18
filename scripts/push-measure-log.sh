#!/bin/bash

# 計測ログ1件をサーバー上でcommitしてpushする（scripts/alp.sh / slow-query.sh から呼ばれる）。
# commit直後にpushするので、サーバーのブランチはoriginの先頭から分岐しない。
# ログのファイル名は毎回異なる（タイムスタンプ・サーバー名入り）ため、pull --rebase でコンフリクトしない。
# 計測結果の表示を止めないよう、失敗しても警告だけで exit 0 する。
# pushできなかったcommitはサーバーに残り、次回の計測時に一緒にpushされる。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 0

# alp.sh 等が tee で保存する集計結果に混ざらないよう、こちらの出力はすべて標準エラーへ
exec 1>&2

LOG_FILE="${1:?usage: $0 <measure-log-file>}"

warn() { echo "warning: $* (計測結果は ${LOG_FILE} に保存済み)"; exit 0; }

branch=$(git symbolic-ref --quiet --short HEAD) || warn "detached HEADのためcommitしない"

# パス指定のcommitなので、サーバー上の他の変更は巻き込まない
git add -- "$LOG_FILE" || warn "git add に失敗"
git commit --quiet -m "計測ログを記録: ${LOG_FILE#measure-logs/}" -- "$LOG_FILE" || warn "commitに失敗"

# ローカルや他サーバーが先にpushしていると拒否されるため、rebaseして数回やり直す
# （-all系で全サーバーが同時にpushする場合もここで吸収する）
# 待ち時間が全サーバーで同じだと再び同時にpushして衝突するので、ランダムにずらす。
# 途中の拒否メッセージは想定内なので捨て、最後まで失敗したときだけ表示する
attempts=6
for i in $(seq 1 "$attempts"); do
  if out=$(git pull --quiet --rebase --autostash origin "$branch" 2>&1 && git push --quiet origin "HEAD:${branch}" 2>&1); then
    echo "pushed: ${LOG_FILE} -> origin/${branch}"
    exit 0
  fi
  git rebase --abort 2>/dev/null
  [ "$i" -lt "$attempts" ] && sleep "$(awk -v s="$RANDOM" -v i="$i" 'BEGIN { srand(s); printf "%.1f", i * 0.5 + rand() * 2 }')"
done
echo "$out"
warn "pushに失敗。commitはサーバーに残り、次回の計測時に一緒にpushされる"
