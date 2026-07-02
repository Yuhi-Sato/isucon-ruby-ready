---
name: isucon-optimization-patterns
description: ISUCONでボトルネック特定後、Ruby（Sinatra + mysql2/pg）アプリのコード改善を行うときに使う。N+1解消・インデックス追加・キャッシュ・静的ファイル配信化・bulk insertなどの定番パターン集。「N+1を直して」「インデックスを追加して」「このエンドポイントを速くして」などのリクエストで使用する。
---

# ISUCON アプリ改善パターン集

## 概要

Sinatra + mysql2 直叩き構成（近年のISUCON公式Ruby実装）での定番改善パターン。
**適用条件（計測シグナル）に合致するものだけを適用する。** シグナルの取り方は isucon-bottleneck-analysis スキル。

変更は必ず「ローカルで編集 → push → デプロイ」の流れ（AGENTS.md）。サーバーのワーキングツリーは直接編集しない。
**1改善ごとにベンチを回して効果を数値で確認する。**

## パターン一覧（計測シグナル → パターン）

| 計測シグナル | パターン |
|---|---|
| クエリCountがリクエスト数の数倍〜数十倍 | 1. N+1解消 |
| EXPLAINで type=ALL / Rows examined ≫ Rows sent | 2. インデックス追加 |
| 同一結果を返す軽くないSELECTが大量 | 3. アプリ内キャッシュ |
| ループ内INSERT/UPDATEが多発 | 4. bulk insert / まとめ書き |
| BODY SUMが大きい・画像URIがSUM上位 | 5. 静的ファイル/画像のnginx配信化（isucon-server-tuning も参照） |
| apptime大でVernierに外部コマンドや重いRuby処理 | 6. アプリコードの直接改善 |

## 1. N+1解消

ループ内クエリを、事前一括取得＋ハッシュ引きに変える。JOINで書けるならJOINでも良い。

```ruby
# BAD: N+1
posts.each do |post|
  post[:user] = db.xquery('SELECT * FROM users WHERE id = ?', post[:user_id]).first
end

# GOOD: WHERE IN + ハッシュ化（O(N)クエリ→2クエリ）
user_ids = posts.map { |p| p[:user_id] }.uniq
users = db.xquery("SELECT * FROM users WHERE id IN (#{user_ids.map { '?' }.join(',')})", *user_ids)
  .each_with_object({}) { |u, h| h[u[:id]] = u }
posts.each { |post| post[:user] = users[post[:user_id]] }
```

注意: `user_ids` が空だと `IN ()` がSQLエラーになる。空なら早期return。

## 2. インデックス追加

```sql
ALTER TABLE comments ADD INDEX idx_post_id (post_id);
-- 複合: WHERE a = ? AND b = ? ORDER BY c → INDEX(a, b, c) の順
ALTER TABLE livestreams ADD INDEX idx_user_score (user_id, score DESC);
```

**最重要の落とし穴: `POST /initialize` がDBをダンプから再構築する問題では、手でALTERしてもベンチのたびに消える。**
初期化処理（init.sh や initialize エンドポイントが流すSQL）にALTER文を追加すること。initialize には制限時間がある（値は当日マニュアルで確認。多くは数十秒）ため、追加後に初期化が時間内に終わるか確認する。

注意: `DESC` 付きインデックスが効くのはMySQL 8.0以降（5.7では昇順で作られる）。`sudo mysql -e "SELECT VERSION();"` でバージョンを確認する。
適用後は `EXPLAIN` で type が ref/range 等に変わったことを確認する。

## 3. アプリ内キャッシュ

外部ミドルウェア（Redis等）を入れる前に、プロセス内メモリキャッシュで足りるか検討する（導入・運用コストが圧倒的に低い）。

```ruby
# 更新頻度が低いマスタデータや集計値に。TTLはデータの更新頻度と
# ベンチの整合性チェックの厳しさに合わせて決める（迷ったら1秒から）
CACHE = {}
CACHE_MUTEX = Mutex.new

def cached(key, ttl: 1)
  CACHE_MUTEX.synchronize do
    entry = CACHE[key]
    return entry[:value] if entry && entry[:expires_at] > Time.now
    value = yield
    CACHE[key] = { value: value, expires_at: Time.now + ttl }
    value
  end
end
```

注意:
- **マルチプロセス（puma workers / unicorn）ではプロセスごとに別キャッシュ**。整合性が問題になるデータには使わない
- `POST /initialize` でキャッシュをクリアすること（前回ベンチのデータが残ると整合性チェックで落ちる）
- ベンチの整合性チェックが厳しい値（更新直後に読まれる値）はキャッシュしない

## 4. bulk insert / まとめ書き

```ruby
# BAD: ループ内INSERT
records.each { |r| db.xquery('INSERT INTO logs (a, b) VALUES (?, ?)', r[:a], r[:b]) }

# GOOD: 1クエリにまとめる
values = records.map { '(?, ?)' }.join(',')
db.xquery("INSERT INTO logs (a, b) VALUES #{values}", *records.flat_map { |r| [r[:a], r[:b]] })
```

## 5. 画像・静的ファイルの配信改善

- DBにBLOBで入っている画像は、初回アクセス時またはinitialize時にファイルへ書き出し、以降nginxが直接配信する（`try_files` で「ファイルがあればnginx、なければアプリ」）
- アプリを通しているCSS/JS/画像は nginx の `location` で直接配信する（設定は isucon-server-tuning スキル）

## 6. アプリコードの直接改善

Vernierで特定した重い処理の定番:

- 外部コマンド呼び出し（`` `openssl`  ``, `system(...)`）→ Ruby組み込み（`OpenSSL::`, `Digest::`）に置換
- ループ内での正規表現コンパイル・重い文字列生成 → ループ外へ
- 全件取得してRubyで絞り込み → SQLの `WHERE` / `LIMIT` に押し込む
- `ORDER BY RAND()` → 主キー範囲での乱択などに置換

## よくある失敗

| 失敗 | 対策 |
|---|---|
| インデックスを手で貼り、initialize で消えて「効かない」と誤判断 | 初期化処理にALTERを組み込む |
| キャッシュで古い値を返し整合性チェックで大幅減点 | initializeでクリア。更新される値はTTLを短く、または使わない |
| 複数パターンを同時投入して、どれが効いたか不明 | 1改善→push→デプロイ→`make bench`→計測 |
| 計測シグナルなしで「定番だから」と適用 | 各パターンのシグナル列に合致してから着手 |
| `IN ()` 空リストでSQLエラー | 空チェックを必ず入れる |
