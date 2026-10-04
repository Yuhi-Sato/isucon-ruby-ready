# アプリのsystemdユニットの取り込み確認

アプリのsystemdユニット（`${SERVICE_NAME}.service` と drop-in の `${SERVICE_NAME}.service.d/`）は、`make setup-sN` の `scripts/get-conf.sh` で `sN/etc/systemd/system/` に取り込まれ、`make bench-prep` の `scripts/deploy-conf.sh` で `/etc/systemd/system/` に反映される（`daemon-reload` は `scripts/restart.sh` が行う）。

ただし `get-conf.sh` は**その時点の `scripts/vars.sh` の `SERVICE_NAME`** でユニットを探す。`make setup-sN` は `isucon-service-name-setup` スキルで `SERVICE_NAME` を直す前に走るので、ユニットが取り込まれていない（warningが出ただけ）か、別のユニットが取り込まれていることがある。このままだと、ユニットを変えても `sN/` に変更先が無い。**`isucon-service-name-setup` スキルが終わってから**確認する。

## 手順

1. 取り込み済みか確認する（`SERVICE_NAME` は `scripts/vars.sh` の値）

   ```bash
   ls s1/etc/systemd/system/
   ```

   `${SERVICE_NAME}.service` があれば、中身の `ExecStart` 等が実サーバーのものと一致するか確認して終わり

   ```bash
   ssh s1 "systemctl cat <SERVICE_NAME>.service"
   ```

2. 無い・別のユニットしか無い場合は、`SERVICE_NAME` を直したブランチをサーバーで checkout してから `get-conf.sh` を実行する

   ```bash
   ssh s1 "cd <サーバー上のリポジトリ> && ./scripts/get-conf.sh && git status --short"
   ```

3. `sN/etc/systemd/system/` だけを commit・push する。`get-conf.sh` は `sN/etc/mysql`・`sN/etc/nginx`・`sN/env.sh` もサーバーの現状で上書きするため、まだ反映していない手元の変更（ltsv設定等）が巻き戻っていたら commit に含めず元に戻す

   ```bash
   ssh s1 "cd <サーバー上のリポジトリ> && git add s1/etc/systemd/system && git commit -m 'chore: アプリのsystemdユニットを取り込む' && git checkout -- s1/ && git push"
   ```

   s2/s3でもアプリを動かす構成なら、それぞれのサーバーで同じ手順を行う

4. 別のユニットを取り込んでいた場合（例: Go実装の `isu-go.service`）は `sN/etc/systemd/system/` から削除して commit する。残すと `deploy-conf.sh` が `/etc/systemd/system/` に置き続ける

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `SERVICE_NAME` を直す前の `get-conf.sh` の warning を見落とし、ユニットが `sN/` に無いまま進める | 手順1で `sN/etc/systemd/system/${SERVICE_NAME}.service` の有無を必ず見る |
| サーバー上でユニットを直接編集（`systemctl edit` 等）し、`sN/` に戻さない | 次の `bench-prep` で `sN/` の内容に上書きされて消える。変更は `sN/etc/systemd/system/` に入れて commit・push → `make bench-prep` で反映する |
| `get-conf.sh` 実行後に `git add .` し、未反映のnginx/MySQL設定の変更を巻き戻した状態で commit してしまう | 手順3のとおり `sN/etc/systemd/system` だけを add する |
