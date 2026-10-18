# 初動手順（TODOリスト）

競技開始直後の初動を、担当者ごとの手順とTODOにまとめたもの。完了したらチェックする。

| 担当 | GitHub | やること |
| --- | --- | --- |
| Yuhi-Sato | [Yuhi-Sato](https://github.com/Yuhi-Sato) | リポジトリ作成、AWS構築、秘密鍵共有、テスト、構成図 |
| u-ktk | [u-ktk](https://github.com/u-ktk) | マニュアルの読み込み |
| garebare | [garebareDA](https://github.com/garebareDA) | サービス名設定、ベンチ実行、計測設定 |

## 全体の流れ

```
[Yuhi-Sato] 前日まで: リポジトリ作成
     ↓
[Yuhi-Sato] 当日: AWS構築 → インスタンス作成 → 秘密鍵共有
     ↓
 ├─ [Yuhi-Sato] isucon-ruby-testing / update-architecture-diagram
 ├─ [u-ktk]     マニュアルを読み込む
 └─ [garebare]  サービス名設定 → ベンチ実行 → 計測設定
```

- garebareは、Yuhi-Satoの「秘密鍵共有」が済むまでサーバーに入れない
- u-ktkのマニュアル読み込みは、鍵共有を待たずに最初から始められる

---

## Yuhi-Sato

### ISUCON前日まで

- [ ] チームリポジトリを作成する
  ```bash
  gh repo create <team-repo> --template Yuhi-Sato/isucon-ruby-ready --private --clone
  ```

### 当日（最優先。他メンバーがこれ待ち）

- [ ] AWSを構築する（パブリックサブネット、SSH・HTTPなどを許可するセキュリティグループ）
- [ ] EC2インスタンスを作成する
- [ ] キーペアを作成し、秘密鍵（`.pem`）をメンバーに共有する

### 共有後

- [ ] `isucon-ruby-testing`を実行する（リファクタ前の回帰テスト環境を作る）
- [ ] `update-architecture-diagram`を実行する（サーバ構成・通信経路の図をmermaidで描く）

---

## u-ktk

- [ ] マニュアルを読み込む

---

## garebare

サーバーに入れるようになってから始める。順序には意味があるので、上から順に進める。

- [ ] `isucon-service-name-setup`を実行する
  - `scripts/vars.sh`の`SERVICE_NAME` / `APP_DIR` / `DB_SERVICE_NAME`を実サーバーに合わせる
  - ズレたままベンチを回すと古いアプリを計測してしまうため、最優先
- [ ] ベンチマークを実行する
  - [ ] `scripts/save-bench-log.sh`を実行する
  - [ ] ベンチ結果はポータルサイトで確認する
- [ ] `isucon-measurement-setup`を実行する

---

## 初動の完了条件

- [ ] Yuhi-Sato: インスタンスを作成し、秘密鍵を共有した
- [ ] Yuhi-Sato: `isucon-ruby-testing`と`update-architecture-diagram`を実行した
- [ ] u-ktk: マニュアルを読み込んだ
- [ ] garebare: `isucon-service-name-setup`、ベンチ実行、`isucon-measurement-setup`を済ませた

ここまでが初動。以降は`roles.md`の役割分担と`tasks.md`で進める。
