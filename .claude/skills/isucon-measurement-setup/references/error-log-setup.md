# systemd / nginx / MySQL のエラーログ設計

502やベンチFAIL発生時に「まずどこを見れば原因が分かるか」を迷わないよう、3種のエラーログの置き場所と確認手段をあらかじめ揃えておく。
アクセスログ（`make alp`）やスロークエリログ（`make slow-query`）と違って集計はせず、**異常時に生ログを直接読む**運用が前提。

推測でパスや設定を決め打ちしない。問題によってディストリ・パッケージが異なり、デフォルト設定も揺れるため、必ず実サーバーで現状を確認してから合わせる。

## 手順

1. **systemd（アプリ）: 標準出力/エラーがjournalに出ているか確認する**

   ```bash
   ssh s1 "systemctl cat <SERVICE_NAME>" | grep -i standard
   ```

   `StandardOutput=journal` / `StandardError=journal`（または未設定＝デフォルトでjournal）になっていればOK。`StandardError=null`や`2>/dev/null`相当のリダイレクトがあると例外スタックトレースが握りつぶされるため、その場合はユニットファイルから該当行を削除する。
   確認・購読は`make watch-service-log`（`journalctl -u <SERVICE_NAME> -f`）で行う。

2. **nginx: エラーログのパス・レベルを確認する**

   ```bash
   ssh s1 "sudo nginx -T | grep error_log"
   ```

   多くのディストリでデフォルトは `error_log /var/log/nginx/error.log;`（レベル省略時は`error`）。`crit`や`alert`など`error`より狭いレベルに変更されていなければ、明示的な変更は不要。
   `scripts/vars.sh`の`NGINX_ERROR_LOG`が実際のパスと一致しているか確認し、ずれていれば合わせる。

   レベルを変更したい場合は`tool-config/nginx/error-log.conf`を`http {}`ブロック（または`server {}`）に貼り付ける。

3. **MySQL: エラーログのパス・verbosityを確認する**

   ```bash
   ssh s1 "sudo mysql -e \"SHOW VARIABLES LIKE 'log_error%'\""
   ```

   `log_error`が実際の出力先。`scripts/vars.sh`の`DB_ERROR_LOG`と一致しているか確認する。
   `log_error_verbosity`のデフォルトは3（エラー+警告+注意）。ベンチ負荷でDB接続の張り直しが多いアプリだと`Aborted connection`のNote/Warningが大量に出ることがあるが、**これはログ設定の問題ではなくアプリ側のコネクション使い回しの問題**なので、まずアプリ層（コネクションプール・タイムアウト設定）を疑う。ディスクを圧迫するほど肥大化する場合の緊急回避としてのみ`tool-config/mysql/error-log-verbosity.cnf`（`log_error_verbosity = 2`）を`my.cnf`に足す。

4. commit・push → `make bench-prep` で反映

5. `make watch-error-log`（nginx/MySQLのエラーログを`tail -F`で追尾）と`make watch-service-log`（アプリのjournal）を並行して確認できることを確認する

## ログのローテーション/クリア

`make rm-logs`（`make bench-prep`にも含まれる）で、アクセスログ・スロークエリログと同様にnginx/MySQLのエラーログも`truncate`される。ベンチ1回ごとに直近の実行分だけが残るため、過去の実行と混同しない。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| パスを確認せず`scripts/vars.sh`のデフォルト値のまま使い、実際には別パス（syslog経由等）に出ていて何も見えない | 手順1-3で必ず実サーバーの実際の設定を確認する |
| `Aborted connection`の大量ログを見て`log_error_verbosity`を下げて終わりにする | ログを消す前に、なぜ接続が頻繁に切れているか（アプリのコネクション管理）をisucon-bottleneck-analysisで調べる |
| ユニットファイルの`StandardError`設定に気づかず、例外が起きているのにjournalに何も出ないと勘違いする | 手順1で`systemctl cat`を確認する |
| エラーログを一切truncateせず、当日の別の時間帯のベンチ結果と混ざって原因特定に時間がかかる | `make rm-logs`/`make bench-prep`を毎回のベンチ前に実行する |
