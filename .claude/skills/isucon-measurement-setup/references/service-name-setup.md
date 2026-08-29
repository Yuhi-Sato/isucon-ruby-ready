# サービス名・scripts/vars.sh変数のセットアップ

`scripts/vars.sh` 冒頭の `SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME` はデフォルト値のままだと問題の実環境と一致しないことが多い。これがズレたまま `make bench-prep` すると、古いアプリを再起動・計測してしまい、ベンチ結果が無意味になる。**初動調査の中でも最優先で直す。**

このチームは **Ruby 実装**で進める（デフォルトは `APP_DIR=./webapp/ruby`、`SERVICE_NAME=isu-ruby`）。

## 手順

1. サーバー上で実サービス名を特定する（SSH・読み取り専用）

   ```bash
   ssh s1 "systemctl list-units --type=service | grep -iE 'isu|ruby|mysql|maria|nginx'"
   ```

2. 言語実装を確認する（Go で動いていないか）

   ISUCON の問題によっては別言語の実装（例: `isu*-go.service`）が初期稼働になっている。そのままだと Ruby の `SERVICE_NAME` を設定しても空振りし、Go 実装の方を再起動・計測してしまう。手順1で、Go（または他言語）実装が active で、Ruby 実装がサービスとして存在するなら Ruby に切り替える。`PREFIX` は問題に応じたもの（例: `isucon14`、`isupipe`、`isuride` など）

   ```bash
   ssh s1 "sudo systemctl disable --now <PREFIX>-go.service || true; sudo systemctl enable --now <PREFIX>-ruby.service"
   ```

   切り替え後の Ruby サービス名を次の `SERVICE_NAME` 設定に使う。

3. 見つかった値を `scripts/vars.sh` の「問題によって変わる変数」ブロックに反映する

   ```bash
   APP_DIR=./webapp/ruby        # webapp/ruby 以外の構成ならここを変更
   SERVICE_NAME=isu-ruby        # 手順1で見つけた実サービス名（例: isupipe-ruby.service）
   DB_SERVICE_NAME=mysql        # MariaDB出題なら mariadb 等に変更
   ```

4. ローカルでcommit・push → サーバー側で `git pull`（`make deploy` / `make bench-prep` の先頭で自動実行される）が通ることを確認する

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `SERVICE_NAME` が違うまま `make bench-prep` して古いアプリを計測する | 手順1で実サービス名を確認してから最初のベンチに進む |
| Go（または他言語）実装が active なのに Ruby の `SERVICE_NAME` だけ設定して空振りする | 手順2で Go 実装を停止し Ruby 実装へ切り替えてから `SERVICE_NAME` を設定する |
| `.service` 拡張子を含めて設定してしまう | `scripts/vars.sh` 内では拡張子なしの unit 名（`systemctl restart` にそのまま渡る値）を使う |
| MariaDB出題なのに `DB_SERVICE_NAME=mysql` のまま | `systemctl list-units` の結果で `mariadb` 等になっていないか確認する |
| `APP_DIR` を直さず `webapp/ruby` 前提のコマンドが空振りする | リポジトリ構成が異なる問題では `APP_DIR` も合わせて修正する |
