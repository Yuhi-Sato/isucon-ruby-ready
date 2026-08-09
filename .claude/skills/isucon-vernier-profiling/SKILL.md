---
name: isucon-vernier-profiling
description: ISUCONでVernierサンプリングプロファイラを導入・実行するときに使う。gem追加、Rack middlewareへの組み込み（AI向けMarkdown出力）、CLIでの単発スクリプトプロファイリング、プロファイルの読み方をまとめる。「Vernierを入れて」「アプリCPUのボトルネックを調べたい」「vernier-viewの結果を見て」などのリクエストで使用する。
---

# Vernierプロファイリング

## 概要

[Vernier](https://github.com/jhawthorn/vernier) はRuby 3.2.1以上が必要のサンプリングプロファイラ。問題のRubyバージョンが古い場合は導入できない。
出力形式はVernierのMarkdown形式（AI向けフォーマット。ホットスポット・スレッド別集計をテキストで出す）を使う。GUIビューアを開かずに`cat`やSSH経由でエージェントがそのまま読める。

`isucon-bottleneck-analysis`スキルの手順4（slow-queryが軽いのにapptimeが大きい＝アプリCPUが疑わしいとき）から呼ばれる想定。

## 1. gemの追加

**ローカル（手元のリポジトリ）で実行し、`Gemfile` / `Gemfile.lock` の変更をコミット・pushする。** サーバー上で直接実行しないこと（サーバーで実行するとGemfile.lockの変更が残り以後の`git pull`がconflictする）。

```bash
make add-profiling-gems
git add Gemfile Gemfile.lock
git commit -m "Add vernier"
git push
```

## 2. アプリへの組み込み（Webリクエスト単位）

`config.ru` に以下のようなmiddlewareを追加する（Sinatra/Rackアプリを想定）。リクエストごとに記録すると重いため、環境変数などで有効/無効を切り替えられるようにしておくと当日の計測がしやすい。

```ruby
# config.ru
require "vernier"
require "fileutils"

use Rack::Static # など、既存のmiddlewareの後に追加

if ENV["ENABLE_VERNIER"] == "1"
  use Class.new do
    def initialize(app)
      @app = app
    end

    def call(env)
      FileUtils.mkdir_p("tmp/vernier")
      response = nil
      result = Vernier.trace do
        response = @app.call(env)
      end
      result.write(out: "tmp/vernier/#{Time.now.strftime('%Y%m%d-%H%M%S-%L')}.md", format: "markdown")
      response
    end
  end
end
```

`Vernier.trace(out: "...")`のように直接パスを渡すと（Firefox Profiler向けの）JSON形式でネイティブに書き出されてしまいMarkdown形式を選べないため、必ず`Vernier.trace`が返す`Result`を受け取ってから`result.write(out:, format: "markdown")`で明示的に書き出す。

## 3. スクリプト単体をCLIでプロファイリングする

上記middlewareはWebリクエスト単位の計測用。initialize処理やrakeタスク、バッチ処理など「一回だけ実行するコマンド」を直接プロファイルしたいときは、`vernier run`コマンドに`--format markdown`を付けて使う。

```bash
vernier run --format markdown --output-dir tmp/vernier -- ruby path/to/script.rb
```

- `--format markdown`: middlewareと同じAI向けMarkdown形式（`.vernier.md`）で出力する。`vernier run --help`には表示されないオプションだが、実際に動作する（実機で動作確認済み）
- `--output-dir tmp/vernier`: `make vernier-view`が参照する場所に合わせる（省略するとカレントディレクトリに出力される）
- 他に `--interval`（サンプリング間隔）、`--allocation-interval`（アロケーションサンプリング間隔）なども指定できる（`vernier run --help`参照）

出力後は同じく`make vernier-view`で確認できる。

## 4. プロファイルの閲覧・読み方

```bash
make vernier-view
```

直近のMarkdownファイルをそのまま標準出力に表示する（サーバー上で`cat`するだけなので、SSH経由でエージェントが直接読める）。出力は以下のセクション構成:

- **Summary**: mode・duration・サンプル数・スレッド数など
- **Top Hotspots**: self-weight比率が高い順の関数一覧。ここを見てJSONシリアライズ・テンプレート描画・外部コマンド呼び出し等の重い処理を特定する
- **Threads**: スレッドごとのサンプル数・weight
- **Hot Files**: ファイル単位・行単位のサンプル比率

視覚的にフレームグラフを見たい場合は、middlewareの`format: "markdown"`を`format: "firefox"`に変えて出力したJSONファイルを [profiler.firefox.com](https://profiler.firefox.com) にドラッグ&ドロップする。

## よくある失敗

| 失敗 | 対策 |
|---|---|
| `Vernier.trace(out: "profile.md")`のように直接パスを渡してMarkdownにならない | `Vernier.trace`が返す`Result`を受け取り、`result.write(out:, format: "markdown")`を明示的に呼ぶ |
| `make add-profiling-gems`をサーバー上で実行し`git pull`がconflict | ローカルで実行してコミット・pushする |
| リクエストごとにVernierを常時有効化してレイテンシが悪化 | `ENABLE_VERNIER`等の環境変数で必要なときだけ有効化する |
