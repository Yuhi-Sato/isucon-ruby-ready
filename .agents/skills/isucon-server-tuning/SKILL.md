---
name: isucon-server-tuning
description: ISUCONで複数台構成への分割（DB分離・アプリ複数台）、systemdユニットの調整、使わないサービスの停止を行うときに使う。「DBを2台目に移して」「複数台構成にして」「アプリを2台に広げて」「systemdの起動順を直して」などのリクエストで使用する。MySQL/nginxの設定値チューニング自体は isucon-mysql-tuning / isucon-nginx-tuning スキルを使う。
---

# ISUCON サーバー構成・複数台分割

## 概要

インフラ設定の変更は `make get-conf` で取得した `s1/` `s2/` `s3/` 以下のファイルを編集し、
`make bench`（内部で `deploy-conf`）で反映する。**サーバー上の /etc を直接編集しない**（git管理から外れて再現できなくなる）。

設定ファイルの中身のチューニングは専用スキルへ:

- **MySQL（my.cnf・buffer pool・I/O設定など）** → isucon-mysql-tuning スキル
- **nginx（worker・keepalive・静的配信・UNIXソケットなど）** → isucon-nginx-tuning スキル

このスキルが扱うのは、サーバーの役割分担（複数台構成）・systemdユニット・サービスの止め方。

## アプリサーバー（puma / unicorn）

- workers/threads構成の詳細な判断基準は `isucon-puma-tuning` スキルを参照。YJIT/GCなどランタイム設定は `isucon-ruby-runtime-tuning` スキルを参照
- 設定ファイルは `webapp/ruby` 以下（puma.rb / unicorn.rb）またはsystemdユニットの起動コマンドにある
- **systemdユニット（`/etc/systemd/system/*.service` 等）は `make get-conf` / `sN/` の管理対象外。** `/etc` 直接編集禁止の原則の例外として、`sudo` で直接編集してよい（競技中いつでも）。ただし変更内容は必ず `docs/` にメモを残し、他メンバー・再起動試験時に再現できるようにする
- systemdユニットを変更した場合は `sudo systemctl daemon-reload` が必要（`make restart` に含まれる）
- アプリがDBより先に起動して接続失敗する場合は、アプリのユニットに `After=<DB_SERVICE_NAME>.service` / `Restart=always` を追加する（起動順の問題。再起動試験で発覚しやすい）

## 複数台構成への分割

典型: **s1 = nginx + アプリ、s2 = DB専用、s3 = アプリ追加**。分割は「1台のCPU/メモリが飽和している」ことを `dstat` / `top` で確認してから行う。

### DBをs2に分離する手順

1. s2で `make setup` / `make set-as-s2` / `make get-conf` 済みであることを確認（README参照）
2. s2の `s2/etc/mysql/` で `bind-address = 0.0.0.0` にする（デフォルトは127.0.0.1で外部から繋がらない）
3. アプリ用MySQLユーザーがリモート接続可能か確認: `CREATE USER 'isucon'@'%' ...` / `GRANT`
4. s1の `s1/env.sh` のDBホスト環境変数（`ISUCON_DB_HOST` 等、問題により名前が異なる）をs2のプライベートIPに変更
5. push → 各サーバーで `git pull && make deploy-conf && make restart` で反映（次のベンチ直前なら `make bench` にまとめても良い。ただし他メンバーの計測を破壊しないこと）
6. s1のMySQL、s2のnginx/アプリなど**使わないサービスは止める**: `sudo systemctl disable --now <DB_SERVICE_NAME>`（サービス名は `mysql` / `mariadb` 等、Makefileの `DB_SERVICE_NAME` に合わせる。空いたメモリをbuffer_poolに回す → isucon-mysql-tuning スキル）

### アプリを複数台に広げる手順

1. s1のnginxの `upstream` にs3を追加:
   ```nginx
   upstream app {
       server 127.0.0.1:8080 weight=1;
       server <s3のプライベートIP>:8080 weight=1;
       keepalive 128;
   }
   ```
2. s3のアプリのlistenを `0.0.0.0` にし、DB接続先をs2に向ける（env.sh）
3. **セッション/キャッシュがプロセス内メモリ前提だと複数台で壊れる**。先に外部化（DB/クッキー）するか、セッションに依存しないエンドポイントだけを振り分ける
4. デプロイは全台に必要: CIの自動デプロイ or `make remote-deploy-all`

## よくある失敗

| 失敗 | 対策 |
|---|---|
| /etc を直接編集して再現不能になる | `sN/` 以下を編集し `deploy-conf` で反映する |
| bind-address / GRANT 忘れでDB分離後に接続不能 | 分割手順2-3を必ず確認。`mysql -h <IP> -u isucon -p` で疎通確認 |
| initialize が s1 の localhost DB を初期化し続ける | initialize処理のDB接続先も env.sh 経由か確認する |
| プロセス内キャッシュ/セッションのまま複数台化して整合性エラー | 先に外部化してから振り分ける |
| 遊んでいるサーバーのmysql/nginxがメモリを食う | 使わないサービスは `disable --now` で止める |
| systemdユニットの変更を記録せず再起動試験で再現不能 | 変更内容を必ず `docs/` にメモする |
