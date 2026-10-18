---
name: isucon-stackprof-analysis
description: ISUCON後半戦で、stackprofのCPUサンプリング結果（measure-logs/stackprof/ の集計と tmp/stackprof/done/ のdump）を読み、CPU時間の大きい箇所を特定してエンドポイントに対応づけ、issueの根拠となる数値付きの表にまとめる。「プロファイルを見て」「stackprofの結果を分析して」「CPUを食っている箇所は？」「プロファイル取れた」などのリクエストで使用する。導入・取得は`make install-stackprof` / `make stackprof-on` / `make stackprof-report`。担当は分析まで（issue起票は`issue-sync`で別途行う）で、実装・スコア判断は行わない。
---

# stackprof 分析（後半戦）

## 概要

後半戦（`roles/late-game.md`）でgarebareDAが担当する、CPUサンプリング結果の読み方。目的は「CPU時間の大きい箇所を、数値付きでエンドポイントに対応づけ、garebareDA自身がissueにできる形にする」こと。

鉄則（CLAUDE.md）: 推測するな。計測せよ。原因を断定せず、サンプル数・割合を根拠として添える。

## 手順0: 取得（まだ無い場合）

導入と取得の手順は次のとおり。サーバー上は `make ...`、ローカルからは `make remote-...-s1`。

1. `make install-stackprof`（各サーバーで1回。Gemfileは変えない）
2. 評価したいコードを反映する（`branch-pr-workflow`）
3. `make stackprof-on`（`RUBYOPT`で`tool-config/stackprof/boot.rb`を載せてアプリ再起動）
4. ベンチを回す
5. `make stackprof-report`（プロファイラを外して再起動→dump集計→`measure-logs/stackprof/`へ保存・commit・push）

- プロファイル中はオーバーヘッドがあるので、**このベンチのスコアは評価に使わない**
- `stackprof-report` を忘れるとプロファイラが付いたままになる。ベンチ前に必ず外れていることを確認する
- dumpが無いと言われたら、アプリの停止時に`at_exit`が走らなかった可能性がある（`tmp/stackprof/`とアプリのログを確認）

## 手順1: 集計を読む

最新の `measure-logs/stackprof/<日時>-<サーバー>-<ブランチ>-<ハッシュ>.log` を読む（`git pull`で取り込む）。ヘッダーのコミットが、評価したいコードかを最初に確認する。

stackprofのテキスト出力の列:

| 列 | 意味 |
|---|---|
| TOTAL (pct) | そのメソッドが呼び出し先を含めてスタックに居たサンプル数（割合）。遅い処理の入口を探すのに使う |
| SAMPLES (pct) | そのメソッド自身がCPUを使っていたサンプル数（割合）。実際に重い箇所を探すのに使う |

- SAMPLESの大きい順に見て、上位が全体の何%を占めるかを把握する
- `(garbage collection)` `(marking)` `(sweeping)` が大きいときは、オブジェクト生成が多いことを示す。生成元はTOTAL側で探す
- アプリ（`webapp/ruby/`）のフレームと、gem（`mysql2`、`json`、`erb`など）のフレームを分けて読む。gem内が上位でも、呼び出し元のアプリ側が原因のことが多い

## 手順2: 深掘り（呼び出し元・行）

dumpはサーバーの `tmp/stackprof/done/<日時>/` にある。上位のメソッドごとに、サーバー上で呼び出し元と行を見る。

```bash
stackprof tmp/stackprof/done/<日時>/*.dump --method 'App#method'   # 呼び出し元・呼び出し先・行ごとのサンプル
stackprof tmp/stackprof/done/<日時>/*.dump --text --limit 80       # 件数を増やす
```

## 手順3: エンドポイントに対応づける

アプリのコード上で、上位の箇所がどのルート（ハンドラ）から呼ばれるかを追う。最新の `measure-logs/alp/` で、そのエンドポイントの件数・合計時間を引く。プロファイルは「どのコードが重いか」、alpは「どのエンドポイントが多く呼ばれるか」を表すので、両方が大きいものを優先する。

## 手順4: issueの根拠をまとめる

分析結果はu-ktkには渡さない。次の表をissue本文の根拠として使い、`issue-sync`の起票粒度（1エンドポイント1issue）でYuhi-Satoに割り当てる。

```
プロファイル: measure-logs/stackprof/<ファイル名>（コミット <ハッシュ>）
| # | 箇所 | SAMPLES | TOTAL | 対応するエンドポイント | 想定される原因（計測根拠つき） |
```

- 上位N件（目安5〜10）に絞る
- 原因は「〜がSAMPLESの○%を占める」のように数値で書き、断定しない。計測で確かめていないことは「未確認」と書く
- 改善案はissueの「やること」に書く

## やらないこと

- コード変更・デプロイ・ベンチ実行（`stackprof-on`/`stackprof-report`の実行は取得手順なので除く）
- 実装・PR作成（Yuhi-Satoのサイクル）
- プロファイル取得中のベンチ結果でスコアを判断する
