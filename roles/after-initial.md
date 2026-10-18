# 初動以降の役割

初動（`initial-steps.md`）の完了後は、u-ktkが課題を見つけてissueにし、Yuhi-SatoとgarebareDAがPRで解決する。

| 担当 | GitHub | 役割 |
| --- | --- | --- |
| u-ktk | [u-ktk](https://github.com/u-ktk) | mainの計測結果を分析し、issueを作成する。解決済みissueのスコアをmainで確認する |
| Yuhi-Sato | [Yuhi-Sato](https://github.com/Yuhi-Sato) | u-ktkが作成したissueを解決するPRを作成する |
| garebareDA | [garebareDA](https://github.com/garebareDA) | u-ktkが作成したissueを解決するPRを作成する |

issueが足りなくなったら後半戦（`late-game.md`）に移り、garebareDAは実装から離れてCPUプロファイリングを担当する。

## サイクル

```
[u-ktk] mainの計測結果を分析
   ↓
[u-ktk] issueを作成
   ↓
[Yuhi-Sato / garebareDA] issueを1つずつ担当し、ブランチを切ってPRを作成
   ↓
 mainにマージ
   ↓
[u-ktk] mainでベンチを回し、スコアを確認
   ↓
 (最初に戻る)
```

---

## u-ktk

### 分析とissue作成

- [ ] mainでベンチを実行し、`scripts/save-bench-log.sh`で結果を保存する
- [ ] alp / slow-queryなどの計測結果を取り込む（`make remote-measure-all`）
- [ ] 計測結果を分析し、次に直すべき対象を決める
- [ ] 対象ごとにissueを作成する（`issue-sync`の起票粒度に従い、1エンドポイント1issue）
  - タイトル: why + what（対象エンドポイントなど）
  - 本文: 意図 / やること / やらないこと
- [ ] issueをYuhi-SatoとgarebareDAに割り当てる（同じ箇所を2人が触らないようにする）

### スコア確認

- [ ] PRがmainにマージされたら、mainでベンチを回す
- [ ] ポータルでスコアを確認し、issueに結果を書く
- [ ] スコアが上がっていればissueをクローズする。下がった・変わらないときはクローズせずissueに書き、切り戻しを検討する

---

## Yuhi-Sato / garebareDA（共通）

- [ ] 割り当てられたissueを読む（issueが無い・他の人に割り当て済み・競合がある場合は着手せずu-ktkに伝える。自分で起票しない）
- [ ] mainから別のブランチを切る
- [ ] issueを解決する変更を実装する
- [ ] 回帰テストを実行して異常がないことを確認する
- [ ] PRを作成する（作成後、対応issueにPRのURLをコメントする）
- [ ] レビュー後にmainへマージする
- [ ] マージ後のスコア確認はu-ktkに任せ、次のissueに進む

---

## 参照スキル

| 用途 | スキル |
| --- | --- |
| ベンチ結果とスコア規則から次の一手を決める | `isucon-score-strategy` |
| 誰がどのエンドポイントに取り組むかをissueで共有する | `issue-sync` |
| ブランチを切り、ベンチ前にサーバーへ反映する | `branch-pr-workflow` |
| PRを作成する | `create-pr` |
| MySQL設定の最適化 | `isucon-mysql-config-tuning` |
| nginx設定の最適化 | `isucon-nginx-tuning` |
