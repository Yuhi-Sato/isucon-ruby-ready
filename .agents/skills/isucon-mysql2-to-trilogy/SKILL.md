---
name: isucon-mysql2-to-trilogy
description: ISUCONのRuby実装（Sinatra + mysql2直叩き）でDBクライアントをmysql2からtrilogyに移行するときに使う。接続オプション・xquery相当のパラメータバインド実装・結果のhash化・エラークラスの違いと移行手順をまとめる。「mysql2をtrilogyに変えたい」「DBクライアントを変えてパフォーマンスを上げたい」などのリクエストで使用する。
---

# mysql2 → trilogy 移行

## 適用条件（計測シグナル）

- Pumaを複数スレッドで動かしている（`bundle exec puma -t 5:5`等）にもかかわらず、Vernierプロファイルでmysql2のクエリ待ち時間中に他スレッドが進んでいない（GVLが長く握られている）兆候がある
- `bundle install`時にmysql2のネイティブ拡張（libmysqlclient/libmariadb）のビルドで問題が起きている、または当日の環境でmysql2のバージョン起因の不具合が出ている

**上記のような計測・事象なしに「trilogyの方が速いらしいから」だけで着手しない。** クライアント差し替えは影響範囲が広く、見合わない移行コストがかかる。

## 背景

trilogyはGitHubが開発した、libmysqlclient/libmariadbに依存しない純Rubyバインディング + 独自プロトコル実装のMySQL互換クライアント。ネットワークパケットの構築・パース時のメモリコピーを減らす設計で、高負荷時にmysql2より効率的とされる（[GitHub Blog](https://github.blog/open-source/maintainers/introducing-trilogy-a-new-database-adapter-for-ruby-on-rails/)）。Rails 7.1以降は`database.yml`の`adapter: trilogy`としても使えるが、ISUCONの素のSinatra実装でも`Trilogy.new`をmysql2のクライアント同様に直接使える。

## 主要な非互換点（要対応）

| 項目 | mysql2 | trilogy | 対応 |
|---|---|---|---|
| gem / require | `mysql2` | `trilogy` | Gemfileに`gem "trilogy"`を追加。動作確認できるまで`mysql2`は残しておく |
| クライアント生成 | `Mysql2::Client.new(host:, username:, password:, database:, ...)` | `Trilogy.new(host:, port:, username:, password:, database:, connect_timeout:, read_timeout:, ...)` | オプション名はほぼ共通で、`Trilogy.new`に置き換えるだけで済むことが多い |
| パラメータ化クエリ | `client.xquery(sql, *params)`（`?`をクライアント側でエスケープして埋め込み） | **存在しない。** `query(sql)`は生SQL文字列を渡すのみで、escape/quoteメソッドも無い | 下記の「xquery互換ラッパー」を自前で用意する（**最重要・最大の落とし穴**） |
| 結果の取得 | `Mysql2::Result`（`symbolize_keys: true`設定でシンボルキーhashの配列として直接使える） | `Trilogy::Result`。`each_hash`で**文字列キー**のhash、`each`でキー無しの配列 | ラッパー内で`each_hash`の結果をシンボル化し、mysql2と同じ見た目に揃える |
| エラークラス | `Mysql2::Error` | `Trilogy::Error`系（サブクラスの詳細はgemのバージョンで変わりうる） | `grep -rn "Mysql2::Error"`で置換箇所を洗い出し、`rescue Trilogy::Error`に変更した上で実際にエラーを起こして確認する |
| reconnect | `reconnect: true`オプション | 同等オプションの有無をバージョンごとに確認 | 無ければクエリ失敗時に自前でクライアントを作り直すリトライを書く。挙動が変わるため必ずベンチで確認する |

## 移行手順

1. **計測**: Vernierプロファイル・alpの結果でDBクライアント自体がボトルネックだと確認できてから着手する（[isucon-bottleneck-analysis](../isucon-bottleneck-analysis/SKILL.md)参照）
2. **調査**: 既存コードでの使用箇所を洗い出す
   ```bash
   grep -rn "Mysql2::Client\|\.xquery(\|Mysql2::Error" webapp/ruby
   ```
3. **Gemfile追加**: **ローカルで**`bundle add trilogy`を実行し、`Gemfile`/`Gemfile.lock`をコミット・push（サーバー上で直接実行しない。理由はVernier導入と同じ — サーバーでの変更が残ると以後の`git pull`がconflictする）
4. **xquery互換ラッパーを実装**: 既存の呼び出し側コード（`db.xquery(sql, *params)`）を変えずに済むよう、DB接続部分だけ差し替える

   ```ruby
   require "trilogy"

   class TrilogyDB
     def initialize(**opts)
       @client = Trilogy.new(**opts)
     end

     # mysql2のxquery(sql, *params)と同じ呼び出し方を維持するための互換レイヤー
     def xquery(sql, *params)
       interpolated = params.empty? ? sql : interpolate(sql, params)
       @client.query(interpolated).each_hash.map { |row| row.transform_keys(&:to_sym) }
     end

     def close
       @client.close
     end

     private

     def interpolate(sql, params)
       queue = params.dup
       sql.gsub("?") { quote(queue.shift) }
     end

     # trilogyにはescape/quoteメソッドが無いため自前実装する。
     # エスケープ漏れは即SQLインジェクションになるので簡略化しない
     def quote(value)
       case value
       when nil then "NULL"
       when Integer, Float then value.to_s
       when Time then "'#{value.strftime('%Y-%m-%d %H:%M:%S')}'"
       else
         escaped = value.to_s.gsub(/[\0\n\r\\'"\x1a]/) do |c|
           case c
           when "\0" then "\\0"
           when "\n" then "\\n"
           when "\r" then "\\r"
           when "\x1a" then "\\Z"
           else "\\#{c}"
           end
         end
         "'#{escaped}'"
       end
     end
   end
   ```

5. **接続部分の差し替え**: `Mysql2::Client.new(...)`していた箇所（多くはスレッドローカルにコネクションを持つ`connect_db`的なメソッド）を`TrilogyDB.new(...)`に変える。呼び出し側は`db.xquery(sql, *params)`のままで動くはず
6. **エラーハンドリング更新**: `rescue Mysql2::Error`を`rescue Trilogy::Error`に置換
7. **ローカルで疎通確認**: 主要エンドポイントを一通り叩き、結果のhashがシンボルキーで返っていることを確認する
8. **1台に適用してデプロイ → `make bench`で前後比較**。悪化したら即ロールバック（Gemfileの変更を戻してデプロイし直す）

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `interpolate`のエスケープ漏れでSQLインジェクション相当のバグ・クエリエラー | 上記の`quote`実装をそのまま使う。独自に簡略化しない |
| `each_hash`が文字列キーのまま渡り、既存コードの`row[:column]`がnilになる | ラッパー内で必ず`transform_keys(&:to_sym)`する |
| 計測なしに「trilogyの方が速いらしい」で導入し、ベンチが変わらず移行コストだけ失う | 適用条件のシグナルを確認してから着手する |
| サーバー上で`bundle add trilogy`を実行し、`Gemfile.lock`の差分で以後の`git pull`がconflict | ローカルで実行してコミット・pushする |
| 全部のクエリ呼び出し箇所を一気に書き換えて、どこかのSQL構文差異でリクエストが大量に失敗 | まず1〜2エンドポイントで動作確認し、問題なければ残りに展開する |
