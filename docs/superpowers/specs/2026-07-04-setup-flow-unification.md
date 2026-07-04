# セットアップフロー統合・CI変数化 設計書

`/grill-with-docs` セッションでの検討結果。旧セットアップフロー（[2026-07-01-isucon-ruby-ready-design.md](2026-07-01-isucon-ruby-ready-design.md)）実装後に発見された問題点への対応であり、最優先の最適化軸は **当日の初動時間の最小化**（SSHアクセス取得から初回ベンチ+計測ループ確立までの時間）とする。

## 発見された問題

1. **TARGET_DIRハードコード**: 旧`setup.sh`が`TARGET_DIR="/home/isucon"`固定。README自身が挙げるprivate_isu型（配布リポジトリルートが`/home/isucon`直下でない）では、tarball展開場所とgit init/push対象がズレて壊れる。
2. **deploy.ymlのs2/s3自動skipが機能しない**: GitHub Actionsのジョブレベル`if`は`secrets`コンテキストを参照できず常に空文字評価となるため、`if: ${{ secrets.SSH_HOST_S2 != '' }}`はSecretsを登録しても常にskipされる。
3. **旧README記載のs2/s3手順が壊れている**: `git clone <url> .`は非空ディレクトリを拒否する。ISUCONサーバーは全台に配布アプリコードが最初から置かれているため、この手順は標準ケースで失敗する。
4. **旧server-setup.shが`make set-as-s1`をハードコード**: s2/s3で使えない。
5. **旧setup.shの`make extract-queries`のタイミング問題**: 当日チェックリスト（APP_DIR修正等）より前に走るため、`webapp/ruby`以外の問題では空のクエリファイルを初回コミットしてしまう。

## 決定

| # | 論点 | 決定 | 理由 |
|---|---|---|---|
| 1 | セットアップフローの形 | ローカル1コマンドに完全統合。`./setup.sh <server> [repo-name] [--dir <path>] [--role <s1\|s2\|s3>]`がSSH経由でtarball展開→サーバーセットアップ→git配線まで実行 | 「サーバーでtarball展開→サーバーでserver-setup.sh→ローカルでsetup.sh」という実行場所の行き来自体が初動の時間ロスと事故（手順の抜け漏れ）の原因になっていた |
| 2 | s2/s3の統合 | `setup.sh`がs2/s3のセットアップ（git配線・`make setup`・`set-as-sN`・`get-conf`）もカバーする。役割は第1引数のSSHホスト名が`s[1-3]`にマッチするかで推定し、`isucon@<IP>`形式など推定不能な場合のみ`--role`で明示する | README記載の手打ちコマンド3連打をなくし、s1と同じ「1コマンド」の体験に揃える。`~/.ssh/config`のHostをs1/s2/s3に揃える既存運用（README「SSH接続の設定」参照）と役割推定の相性が良い |
| 3 | s2/s3の非空ディレクトリ対応 | `git clone`ではなく`git init` → `remote add` → `git fetch origin main` → `git checkout -f -B main origin/main`を使う | 配布リポジトリのアプリコードが既に置かれた非空ディレクトリに対して、チームリポジトリの内容（Makefile・tool-config・webapp含む）を安全に被せるため |
| 4 | CI skip修正 | `SSH_HOST_S1/S2/S3` / `SSH_USER` / `DEPLOY_PATH`をSecretsからRepository Variablesへ移す。`if`条件を`vars.SSH_HOST_S2 != ''`等に修正 | `vars`コンテキストはジョブレベルの`if`から参照可能なため、意図通りの自動skipが実現する。秘密情報として残すのは`SSH_PRIVATE_KEY`（Secret）のみ |
| 5 | 当日適応の責務境界 | `setup.sh`はインフラ準備（ツール導入・git配線・設定取得）のみを担う。Makefile変数（APP_DIR等）の適応やクエリ抽出（`make extract-sql`）は`isucon-initial-recon`スキル（エージェントの初動調査）の責務とする | 問題によらず同一のインフラ手順と、問題ごとに異なる適応作業を分離することで、setup.shを「常に同じ手順で当日最速に通せるもの」として保つ |
| 6 | server-setup.shの位置づけ | 独立ファイルのまま、第1引数で役割（s1/s2/s3）を受け取るよう変更する | s1/s2/s3で同一スクリプトを共用できる。`gh`未認証・ssh-agent不調などローカル経由が使えない異常時に、サーバー上で`sh server-setup.sh <role>`を直接実行するフォールバック手段としても独立して機能する |

## 用語の境界（[CONTEXT.md](../../../CONTEXT.md)参照）

「セットアップ」と「初動調査」の責務境界は本設計の中心的な決定であり、詳細な定義は`CONTEXT.md`の用語集を参照する。

## 検証状況

- `shellcheck` / `bash -n` / `actionlint`による静的検証、および`setup.sh`の引数パース・役割推定ロジックのローカル実行確認は実施済み
- 実サーバー（練習用EC2）でのend-to-end検証（tarball展開→server-setup.sh→git push、およびs2/s3のgit init+fetch+checkout）は未実施。次回素振り時に確認する
