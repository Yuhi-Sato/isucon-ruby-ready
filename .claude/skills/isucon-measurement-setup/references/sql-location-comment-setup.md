# SQLクエリ位置コメントのセットアップ

`make slow-query`（performance_schema）の出力にはSQL文自体は出るが、**アプリのどのファイル・何行目が発行したクエリかは分からない**。同じテーブルへの類似クエリが複数箇所にあると、都度アプリを`grep`して発行元を探すことになる。mysql2のクエリ発行をprependで横取りし、SQL文の先頭に`/* file:line */`形式のコメントを埋め込むことで、スロークエリの結果から発行元を直接特定できるようにする。

## 手順

1. `webapp/ruby/lib/sql_location_comment.rb`（既存のlib配置があればそれに合わせる）を作成する

   ```ruby
   module SqlLocationComment
     def query(sql, options = {})
       # xquery 経由だと直近フレームが xquery 自身になるので、アプリ側の行を取るために飛ばす
       location = caller_locations.find { |frame| frame.base_label != 'xquery' }

       if location
         file = File.basename(location.path)
         line = location.lineno
         sql = "/* #{file}:#{line} */ #{sql}"
       end

       super(sql, options)
     end
   end
   Mysql2::Client.prepend(SqlLocationComment)
   ```

2. `Mysql2::Client.new`（DB接続確立）より前に読み込まれるようrequireする（`config.ru`やDB接続をまとめたファイルの先頭など）

   ```ruby
   require_relative "lib/sql_location_comment"
   ```

3. commit・push・デプロイ後、ベンチを1回回してから `make slow-query` の詳細ブロック（`\G`縦形式）でクエリ本文の先頭に `/* app.rb:123 */` のようなコメントが付いているか確認する

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `Mysql2::Client.new`より後にrequireし、一部のクエリにコメントが付かない | DB接続確立前、アプリのエントリポイントの最上部でrequireする |
| ORM/ラッパー経由のクエリで`caller_locations`がライブラリ内部のフレームを指し、行番号がアプリコードを指さない | ラッパー側のメソッド名を`base_label`の除外条件に追加する（`xquery`と同様） |
| 導入前に取ったslow-queryの結果と比較して「コメントが付いていない」と勘違いする | 導入後に改めてベンチを1回回し、そのログで確認する |
| コメント付与自体はSQL文字列に前置するだけで実害はないが、最終計測前に計測用コードとして無効化するか判断せず放置する | isucon-final-checkのタイミングで他の計測用コードと合わせて残すか判断する（通常はオーバーヘッドが小さいため残しても問題ない） |
