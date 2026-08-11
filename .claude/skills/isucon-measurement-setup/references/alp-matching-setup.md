# alp matching_groups セットアップ

`make alp` はアクセスログのURIをそのまま集計する。`/api/users/1` と `/api/users/2` のようにIDだけ違うURLは、正規表現でまとめる（`matching_groups`）設定をしないと別々の行に分散し、集計が使いものにならない。**ベースライン計測前に必ず設定する。**

## 手順

1. アプリのルート一覧を洗い出す（Sinatra想定）

   ```bash
   grep -nE "^\s*(get|post|put|delete|patch) " webapp/ruby/*.rb
   ```

2. 可変部分（`:id` 等のパスパラメータ）を持つルートについて、`tool-config/alp/config.yml` の `matching_groups` に正規表現を追加する

   ```yaml
   matching_groups:
     # 例: /api/users/1 と /api/users/2 を /api/users/:id としてまとめて集計する
     - "^/api/[a-zA-Z0-9_]+/[0-9]+$"
     - "^/api/[a-zA-Z0-9_]+/[0-9]+/[a-zA-Z0-9_]+$"
   ```

3. commit・push → 次の `make alp` 実行で、対象URLが1行に集約されているか確認する

## よくある失敗

| 失敗 | 対策 |
|---|---|
| 正規表現がルートのパスパターンと微妙に食い違い、集計が分散したまま | 手順1のルート一覧と実際のURLを見比べて、`^`〜`$`で全体マッチしているか確認する |
| IDだけでなくクエリパラメータ違いでも分散してしまう | `alp` はデフォルトでクエリを無視して集計するため、通常は対応不要。分散する場合はクエリを含むログになっていないか確認する |
| 初動でエンドポイントを洗い出した後、追加実装したルートの分をアップデートし忘れる | 実装追加時やalpの結果に見慣れないURLが並んだ時は、都度 `matching_groups` を見直す |
| `matching_groups` を編集したがベンチもalpも実行し直していない | 設定はconfigファイルを読むだけなので反映にサーバー再起動は不要。次の `make alp` で即反映される |
