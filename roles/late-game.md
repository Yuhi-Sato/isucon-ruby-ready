# 後半戦の役割

`after-initial.md`のサイクルを回し、u-ktkが起票するissueが足りなくなったら後半戦に入る。後半戦では、garebareDAが実装から離れてCPUのサンプルプロファイリングを担当し、解析結果から自分でissueを作成する。

| 担当 | GitHub | 役割 |
| --- | --- | --- |
| u-ktk | [u-ktk](https://github.com/u-ktk) | 初動以降と同じ。mainの計測結果を分析してissueを作成し、スコアを確認する。プロファイルの分析結果は受け取らない |
| Yuhi-Sato | [Yuhi-Sato](https://github.com/Yuhi-Sato) | 初動以降と同じ。issueを解決するPRを作成する。garebareDAが作成したissueも担当する |
| garebareDA | [garebareDA](https://github.com/garebareDA) | 実装（PR作成）から離れ、CPUのサンプルプロファイリングを取得・解析し、結果から自分でissueを作成する（分析結果はu-ktkに渡さない） |

## 後半戦に入る条件

- [ ] 割り当て可能な未着手issueがなくなった（u-ktkの計測結果の分析から、新しく直すべき対象が見つからなくなった）
- [ ] u-ktkが後半戦に入ることを宣言し、garebareDAに伝えた
- [ ] garebareDAが担当中のissue・PRを片付けた（マージ済み、またはYuhi-Satoかu-ktkに引き継いだ）

alp / slow-queryで見えるボトルネックが出尽くした状態が目安。ここから先はアプリのCPU時間の内訳（どのメソッドが時間を食っているか）を見ないと、次の施策が見つからない。

## サイクル

```
[garebareDA] ベンチ中のアプリのCPUをサンプリング
   ↓
[garebareDA] 結果を解析し、CPU時間の大きい箇所を特定
   ↓
[garebareDA] alpと突き合わせ、issueを作成してYuhi-Satoに割り当て
   ↓
[Yuhi-Sato] issueを担当し、PRを作成（以降は after-initial.md と同じ）
   ↓
 mainにマージ → [u-ktk] スコア確認
   ↓
 (最初に戻る。改善後のプロファイルを取り直す)
```

---

## garebareDA

### プロファイリング

- [ ] mainの最新を対象サーバーに反映する（`branch-pr-workflow`）。プロファイルは、評価したいコードが動いている状態で取る
- [ ] `make install-stackprof`でstackprofを導入する（各サーバーで1回。ローカルからは`make remote-install-stackprof-s1`）。アプリの`Gemfile`は変えない。**導入が済むまでプロファイルは開始しない**
- [ ] `make stackprof-on`でプロファイリングを有効にしてアプリを再起動する（ローカルからは`make remote-stackprof-on-s1`）
- [ ] ベンチを回す
  - プロファイラ自体の負荷でスコアが変わるため、**プロファイル取得中のスコアは評価に使わない**。スコア確認用のベンチは別に回す
- [ ] `make stackprof-report`でプロファイリングを止め、dumpを集計する（ローカルからは`make remote-stackprof-report-s1`）
  - 集計は`measure-logs/stackprof/<日時>-<サーバー>-<ブランチ>-<ハッシュ>.log`に保存され、commit・pushされる
  - 実行を忘れるとプロファイラが付いたままになるので、スコア確認のベンチ前に必ず実行する

### 解析とissue作成

- [ ] `isucon-stackprof-analysis`スキルで、CPU時間の大きい順に、メソッド / 行 / 呼び出し元を洗い出す
- [ ] 上位の箇所を、どのエンドポイントから呼ばれているかに対応づける（alpの結果と照らす）
- [ ] 対象ごとにissueを作成する（`issue-sync`の起票粒度に従い、1エンドポイント1issue）
  - タイトル: why + what（対象エンドポイントなど）
  - 本文: 意図 / やること / やらないこと。根拠としてプロファイルのログ（`measure-logs/stackprof/`のファイル名）とサンプル数・割合を書く
  - 推測で原因を断定しない。計測できた数値を添える
- [ ] issueをYuhi-Satoに割り当てる（実装担当が1人なので、優先度の高い順に並べる）
- [ ] 分析結果をu-ktkに渡す必要はない（issueが成果物）
- [ ] 改善PRのマージ後は、プロファイルを取り直して効果と次の上位を確認する

### やらないこと

- 実装・PR作成（Yuhi-Satoのサイクルに任せる）
- プロファイル取得中のベンチ結果でスコアを判断する

---

## u-ktk（後半戦での変更）

- [ ] 初動以降と同じく、mainの計測結果（alp / slow-queryなど）を分析してissueを作成する。プロファイルの分析はgarebareDAが担当するので、結果を受け取る・取り込む必要はない
- [ ] issueをYuhi-Satoに割り当てる際は、garebareDAが作成したissueと同じ箇所を触らないようにする
- [ ] マージ後のスコア確認は`after-initial.md`と同じ

## Yuhi-Sato（後半戦での変更）

- [ ] `after-initial.md`の共通手順どおりに、割り当てられたissueを1つずつ解決する
- [ ] 実装担当が1人になるので、u-ktkとgarebareDAの両方がissueを作成するので、溜まったら優先度順に着手する。同じ箇所を触るissueが重なったらu-ktkに相談する

---

## 参照スキル

| 用途 | 担当 | スキル |
| --- | --- | --- |
| mainの最新をサーバーへ反映する | garebareDA | `branch-pr-workflow` |
| stackprofの結果を分析する | garebareDA | `isucon-stackprof-analysis` |
| issueの起票 | garebareDA / u-ktk | `issue-sync` |
| ベンチ結果とスコア規則から次の一手を決める | u-ktk | `isucon-score-strategy` |
| issueのクローズ | u-ktk | `issue-sync` |
| PRを作成する | Yuhi-Sato | `create-pr` |
