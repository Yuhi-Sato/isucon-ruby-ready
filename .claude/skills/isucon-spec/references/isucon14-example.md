# ISUCON14 の出題仕様（記入例）

[isucon-spec](../SKILL.md) を実際のISUCON14で埋めた例。`/update-isucon-spec` で自分の回の辞書を作るときの、書式・粒度の参考にする。

マニュアルの語を、ログ・DB・ベンチのソースの語に引き直した辞書。語はソースの文字列そのままなので、見つけた語でそのまま検索できる。（未確認）は確認できていない内容。更新は `/update-isucon-spec`。

書式は `/update-isucon-spec` を参照。ベンチのソースは公式リポジトリの `bench/`（ローカル: `~/ghq/github.com/isucon/isucon14/bench`）。
実ログの置き場は `docs/bench/`（`make save-bench-log` で保存する）。

## 当日マニュアル

### 競技環境

#### 変更してはいけない点

| マニュアルの語 | システムの言葉 |
|---|---|
| `envcheck.service` に関わるファイル、`/opt/isucon-env-checker` 内のファイル、`isuadmin` ユーザーに関わるファイル・権限 | 変更すると、追試の `sudo /opt/isucon-env-checker/envcheck` が失敗し、失格になる |

#### 複数スタックの問題

| マニュアルの語 | システムの言葉 |
|---|---|
| ポータル上のサーバー情報が混在 | ポータルのサーバーリスト（`contestant_instances`）に、別の CloudFormation スタックのサーバーの IP が混ざる |

### ベンチマーカーの実行

#### 負荷走行

| マニュアルの語 | システムの言葉 |
|---|---|
| 負荷走行 | ログ先頭 `負荷走行を開始します`、末尾 `負荷走行が終了しました` |
| 初期化処理 | `POST /api/initialize`（30秒）。あわせて `POST /api/owner/owners`・`POST /api/chair/chairs`・`POST /api/app/users` を呼ぶ（この3つは複数回） |
| 負荷テスト（60秒） | ログの `時間経過 tick=` が出る区間（`isucandar.WithLoadTimeout`。`bench/cmd/run.go`） |
| 初期化処理もしくはアプリケーション整合性チェックに失敗すると、負荷走行は即時失敗（FAIL） | ログ末尾 `結果 pass=false` |
| 負荷テスト終了後5秒以内に決済処理を完了 | `time.Sleep(5 * time.Second)`（`bench/benchmarker/scenario/validation.go`） |

#### ベンチマーカーのタイムアウト

| マニュアルの語 | システムの言葉 |
|---|---|
| それ以外のリクエスト 10秒 | 評価リクエスト `POST /api/app/rides/:id/evaluation` が10秒を超えると `ErrorCodeEvaluateTimeout`（`CODE=6`） |

#### 負荷走行の打ち切り

| マニュアルの語 | システムの言葉 |
|---|---|
| 打ち切られた場合はその負荷走行はFAILとして記録 | ログ末尾 `結果 pass=false スコア=<n> 種別エラー数=map[<CODE>:<件数>]`（成功時は `結果 pass=true`、`種別エラー数=map[]`） |
| 負荷走行の実行中にクリティカルエラーが発生する | `CriticalErrorCodes`（下の「クリティカルエラー」の表） |
| 200件以上のワーニング | `ErrorLimit = 200`（※1） |

※1 ワーニングはログの `level=WARN`。`CriticalErrorCodes` に無いエラーコード（下の「ワーニング側」の表）を、`World.handleTickError` が `Warn` で出力して `ErrorCounter.Add` で数える。`CriticalErrorCodes` のエラーも同じ `ErrorCounter.Add` で数える。件数が `ErrorLimit` を超えると、ベンチが `発生しているエラーが多すぎます` を出す（`bench/benchmarker/world/errors.go`、`world.go`）

クリティカルエラー（`CriticalErrorCodes`）

| コード | ログの文言 | 出るケース |
|---|---|---|
| 6 | ユーザーのライド評価がタイムアウトしました | 評価リクエストが `context.DeadlineExceeded` で失敗した（`bench/benchmarker/world/user.go`） |
| 9 | ユーザーが想定していない通知を受け取りました | `ErrorCodeUserNotRequestingButStatusChanged`: リクエストしていないユーザーのリクエストステータスが更新された |
| 10 | 椅子が想定していない通知を受け取りました | `ErrorCodeChairNotAssignedButStatusChanged`: 椅子にリクエストが割り当てられていないのに、椅子のステータスが更新された |
| 11 | ユーザーに想定していないライドの状態遷移の通知がありました | `ErrorCodeUnexpectedUserRequestStatusTransitionOccurred`: ユーザーの RequestStatus が想定外の遷移をした |
| 12 | 椅子に想定していないライドの状態遷移の通知がありました | `ErrorCodeUnexpectedChairRequestStatusTransitionOccurred`: 椅子の RequestStatus が想定外の遷移をした |
| 15 | 椅子がライドの完了通知を受け取る前に、別の新しいライドの通知を受け取りました | `ErrorCodeChairAlreadyHasRequest`: 既にリクエストが割り当てられている椅子に、別のリクエストが割り当てられた |
| 32 | ライドが長時間マッチングされませんでした | ライド要求から30秒たっても、ライドが `MATCHING` のまま（`user.go`） |
| 34 | 評価は完了しているが、支払いが行われていないライドが存在します | 評価リクエストをサーバーが受理した時点で `Request.Paid` が false（`user.go`） |
| 35 | 決済サーバーに誤った支払いがリクエストされました | `進行中のリクエストがありません` / `既に支払い済みです` / `支払い額が不正です`（`bench/benchmarker/world/payment.go`） |

ワーニング側のエラーコード（`CriticalErrorCodes` に無いもの）

| コード | ログの文言 |
|---|---|
| 1 | 椅子の座標送信に失敗しました |
| 2 | 椅子が出発できませんでした |
| 3 | 椅子がライドを受理できませんでした |
| 5 | ユーザーのライド評価に失敗しました |
| 7 | ユーザーがライド履歴の取得に失敗しました |
| 8 | ユーザーが新しくライドを作成できませんでした |
| 13 | 椅子がアクティベートに失敗しました |
| 17 | ユーザー登録に失敗しました |
| 18 | オーナー登録に失敗しました |
| 19 | 椅子登録に失敗しました |
| 20 | 通知APIの接続に失敗しました |
| 21 | ユーザーの支払い情報の登録に失敗しました |
| 22 | オーナーの売り上げ情報の取得に失敗しました |
| 24 | 取得したオーナーの売り上げ情報が想定しているものと異なります |
| 25 | オーナーの椅子一覧の取得に失敗しました |
| 26 | 取得したオーナーの椅子一覧の情報が想定しているものと異なります |
| 27 | 取得した付近の椅子情報が古すぎます |
| 29 | 椅子が受け取った通知の内容が想定と異なります |
| 30 | 取得した付近の椅子情報に不備があります |
| 31 | 付近の椅子情報が想定よりも足りていません |
| 33 | ユーザーが受け取った通知の内容が想定と異なります |

#### 猶予時間

| マニュアルの語 | システムの言葉 |
|---|---|
| `GET /api/app/nearby-chairs` の座標は過去3秒以内の `POST /api/chair/coordinate` に一致 | `ErrorCodeTooOldNearbyChairsResponse`（`CODE=27`）（※1） |
| `GET /api/app/nearby-chairs` に含まれるべき空き椅子 | `ErrorCodeLackOfNearbyChairs`（`CODE=31`）（※2） |
| `GET /api/owner/chairs` の移動距離合計に3秒の猶予 | `ErrorCodeIncorrectOwnerChairsData`（`CODE=26`）（※3） |
| ライドの通知まで30秒の猶予 | `bench/` にこれを直接判定する処理は無い（※4） |

※1 ログ `ID:<椅子ID>の椅子は直近に指定の範囲内にありません`。ベンチは、応答に含まれる椅子が、リクエスト時点でその座標にいたか、直近3秒以内にいたかを検査する（`bench/benchmarker/world/world.go`。ワーニング）
※2 ログ `不足数<n>台`。ベンチは3秒待ってから、応答に含まれるべき空き椅子が欠けていないかを検査する（`world.go`。ワーニング）
※3 ログ `total_distanceの反映が遅いデータがあります (id: <椅子ID>)`。判定に使うのは JSON の `total_distance`・`total_distance_updated_at`（`bench/benchmarker/world/owner.go`。ワーニング）
※4 `bench/` に30秒が出てくるのは、ライドが `MATCHING` のままになる `ErrorCodeMatchingTimeout`（`CODE=32`）だけ

### スコアの計算

- 椅子がライドとマッチした位置から乗車位置までの移動距離の合計 * 0.1
  - データ: `chair_locations.latitude`・`chair_locations.longitude`、`rides.pickup_latitude`・`rides.pickup_longitude`（すべて `INTEGER`）
  - ベンチ: `Request.Score()` の `StartPoint.V.DistanceTo(r.PickupPoint)*FarePerDistance/ForwardingScoreDenominator`（`FarePerDistance = 100`、`ForwardingScoreDenominator = 10`）
- 椅子の乗車位置から目的地までの移動距離の合計
  - データ: `rides.pickup_latitude`・`rides.pickup_longitude`・`rides.destination_latitude`・`rides.destination_longitude`
  - ベンチ: `Request.Sales()` = `InitialFare + PickupPoint.DistanceTo(DestinationPoint)*FarePerDistance`
- ライド完了数 * 5
  - ベンチ: `InitialFare = 500`（`Request.Sales()` に含まれる）
- 最終スコア
  - ベンチ: `Scenario.Score` は、各 `Owner.SubScore` の合計を100で割った値。ログの `スコア=<n>` に出る
- 補足
  - データ: `webapp/sql/1-schema.sql` の `COMMENT` は `latitude` を「経度」、`longitude` を「緯度」と逆に書いている

#### 最終スコア

| マニュアルの語 | システムの言葉 |
|---|---|
| 最後に行った負荷走行がFAIL | ログ末尾 `結果 pass=false` |

### 追試

#### 追試手順

| マニュアルの語 | システムの言葉 |
|---|---|
| FAILもしくは最終スコアの75%以下 | `pass=false`、または `スコア=` が最終スコアの0.75倍以下（`bench/` のソースに該当する処理は無い） |

### 言語賞

| マニュアルの語 | システムの言葉 |
|---|---|
| `language` フィールド | `POST /api/initialize` のレスポンスの JSON `language`（`webapp/ruby/lib/isuride/initialize_handler.rb`） |

## アプリケーションマニュアル

### 用語

#### 地域（region）

| マニュアルの語 | システムの言葉 |
|---|---|
| 地域 | ログ `最終地域情報 名前=<地域名> ユーザー登録数=<n> アクティブユーザー数=<n>` |

#### 時間（tick）

- ベンチマーカーの世界が進む単位。マッチ待ち・迎車・乗車の判定はすべて tick で数える
  - ベンチ: 1 tick = 30ms。負荷テスト60秒の間、tick は実時間に対して一定の速さで進む（観測: `bench_log/04-success-score6192.log` で、`時間経過 tick=1860`（12:59:33.228）から `tick=1920`（12:59:35.028）まで、1.8秒で60 tick 進む。8走行すべてで、最後は `tick=1980`）
  - 換算: 5 tick = 0.15秒、15 tick = 0.45秒、100 tick = 3秒、仮想1時間（60 tick）= 1.8秒
- 椅子は1 tick に1歩しか移動しない。そのため `POST /api/chair/coordinate` の応答が 30ms を超えると、1歩あたりの所要 tick が増える（「椅子」を参照）

#### 距離（distance）と座標（coordinate）

- 距離はマンハッタン距離
  - 仕様: `abs(x1-x2) + abs(y1-y2)`。座標は整数
  - ベンチ: `Coordinate.DistanceTo`（`bench/benchmarker/world/coordinate.go`）
- 座標は `latitude` と `longitude`
  - データ: `chair_locations.latitude`・`chair_locations.longitude`、`rides.pickup_latitude`・`rides.pickup_longitude`・`rides.destination_latitude`・`rides.destination_longitude`（すべて `INTEGER`）

#### 椅子（chair）

- 位置情報を更新するリクエストが成功したことを確認するまでは移動しない
  - 処理: `POST /api/chair/coordinate`
  - ベンチ: `Chair.Tick` が椅子を1 tick に1歩移動させたあと、`SendChairCoordinate` が成功するまで `backoff.Retry` で再試行しながら待つ。その間、椅子は次の移動をしない（`bench/benchmarker/world/chair.go`）

#### オーナー（owner）

- 十分に収益が上げられていることを確認すると更なる椅子の導入を検討
  - ベンチ: ログ `一定の売上が立ったためオーナーの椅子が増加します 名前=<オーナー名> 増加数=<n>`
  - ベンチ: 仮想1時間の最後の tick（`LengthOfHour-1`）に `GET /api/owner/sales` を呼んで売上を確認し、`desiredChairNum(res.Total)` が登録済みの椅子数を上回れば椅子を増やす（`bench/benchmarker/world/owner.go`）
  - 処理: 椅子の追加は `POST /api/chair/chairs`（`Client.RegisterChair`。`bench/benchmarker/webapp/client_chair.go`）
- オーナーの収益
  - ベンチ: ログ `最終オーナー情報 名前=<オーナー名> 売上=<n> 椅子数=<n>`

#### ライド（ride）

- 評価（ユーザーが `COMPLETED` に遷移する際に行う）
  - データ: `rides.evaluation`（`INTEGER`、`NULL` 可）
  - 処理: `POST /api/app/rides/:id/evaluation`
  - ベンチ: ログ `eval reqs=<n> score="[a b c d e]" criteria="[w x y z]"`。`score` は評価点1〜5点それぞれの件数、`criteria` は、`Evaluation.Map()` の順（`Matching`, `Dispatch`, `Pickup`, `Drive`）に並ぶ、各項目に満足したライドの数
- 評価に関係する項目
  - ベンチ: `Request.CalculateEvaluation`。評価点は `1 + 満たした項目の数`（最大5）。ログの `criteria` の4項目に対応する
  - ベンチ: `Matching` はマッチまで100 tick 未満。`Dispatch` は迎車距離が `10 × 椅子の速度` 未満。`Pickup` は、迎車の実時間が理想を超過した分が15 tick 未満。`Drive` は、乗車中の実時間が理想を超過した分が5 tick 未満
  - 秒への換算は「時間（tick）」を参照
- 評価がアプリの評判に影響を与える
  - ベンチ: 仮想1時間（60 tick）ごとに、地域の満足度の数だけユーザーが新規登録する。満足度は、地域のユーザーの平均評価の平均を丸めた値。新規ユーザーの評価の初期値は0（`World.Tick`、`Region.UserSatisfactionScore`）
  - ベンチ: 評価4以上のライドを終えたユーザーは、招待コードの使用が3未満なら、ユーザーを1人招待する（`World.PublishEvent`）
  - ベンチ: ユーザーは、初回のライドで評価1をつけるか、2回以上のライドで平均評価が2以下になると離脱する。地域には最低10人が残る（`bench/benchmarker/world/user.go`、`Region.UserLeave`）
  - ベンチ: ログ `これまでに地域内の評判によって<N>人、既存ユーザーの招待経由で<M>人が新規登録しました`
  - ベンチ: ログ `これまでに低評価なライドによって<N>人が利用をやめました`
  - ベンチ: ログ `<x>%のライドは椅子がマッチされるまでの時間、<y>%のライドはマッチされた椅子が乗車地点までに掛かる時間、<z>%のライドは椅子の実移動時間に不満がありました`
- 運賃 `500 + 乗車位置と目的地の間の距離 * 100`
  - 仕様: クーポンを使うと `距離 * 100` の部分から割り引かれる。運賃の下限は `InitialFare`
  - ベンチ: `Request.Fare()`（`InitialFare`・`FarePerDistance` は「スコアの計算」）
- ライドの状態
  - 処理: `MATCHING`, `ENROUTE`, `PICKUP`, `CARRYING`, `ARRIVED`, `COMPLETED`
  - データ: `ride_statuses`（`chair_sent_at`: 椅子への状態通知日時）

#### クーポン（coupon）

| マニュアルの語 | システムの言葉 |
|---|---|
| 付与された順番に必ず使用 | `coupons.discount`（割引額）、`coupons.used_by`（適用されたライドのID） |

### 通知エンドポイント

| マニュアルの語 | システムの言葉 |
|---|---|
| 状態が変更されてから3秒以内に通知 | `GET /api/app/notification`・`GET /api/chair/notification`（※1） |
| 通知の順序（at least once） | クリティカルエラー `CODE=11`・`CODE=12`（「負荷走行の打ち切り」の表） |

※1 `bench/` に、通知の遅れを3秒で直接判定する処理は無い。関係するのは、クライアントのタイムアウト60秒と、ポーリング間隔 `retry_after_ms`（未指定なら `defaultWaitTime` = 30ms）だけ（`bench/benchmarker/webapp/client_user.go`・`client_chair.go`）

### ライドのマッチング

- 初期状態では `isuride-matcher` が `GET /api/internal/matching` を500msごとにポーリング
  - 処理: 間隔は `ISUCON_MATCHING_INTERVAL`（`/home/isucon/env.sh`）で設定する。変更後は `sudo systemctl restart isuride-matcher.service` で再起動する
  - ベンチ: ライドが30秒 `MATCHING` のままだと `CODE=32`
- マッチングは、待っているライドに空いている椅子を1台紐づける処理
  - データ: 待っているライドは `rides.chair_id IS NULL`。マッチすると `rides.chair_id` に椅子のIDが入る。アプリはライドの作成時に、`ride_statuses` へ `MATCHING` の行を1つ入れる（`POST /api/app/rides`）
  - 処理: 初期実装は、`GET /api/internal/matching` の1回の呼び出しで、`rides.created_at` が最も古い1ライドだけを割り当てる（`webapp/ruby/lib/isuride/internal_handler.rb`）。椅子は `is_active = TRUE` の中から `ORDER BY RAND() LIMIT 1` で選び、空いていなければ最大10回引き直す。乗車位置との距離も椅子の速度も見ない
  - ベンチ: マッチ待ちの満足は、マッチまで100 tick（3秒）未満（「ライド」の評価）。呼び出しが0.5秒ごとで1回に1ライドなので、3秒に割り当てられるのは最大6件
- 椅子が空いている条件
  - データ: 椅子の全ライドについて、`ride_statuses.chair_sent_at` が入った行が6つある。6つは `MATCHING`・`ENROUTE`・`PICKUP`・`CARRYING`・`ARRIVED`・`COMPLETED`
  - 処理: `chair_sent_at` は、椅子がその状態の通知を受け取るときに `chair_handler.rb` が入れる。初期実装の空き判定は、`internal_handler.rb` の `COUNT(chair_sent_at) = 6` を使う副問い合わせ
  - ベンチ: ユーザーが評価を送ると `COMPLETED` が付く（「ライド」の評価）。椅子はその通知を受け取るまで空かない
  - ベンチ: 空いていない椅子に別のライドを割り当てると `CODE=15`（「負荷走行の打ち切り」の表）
- 迎車距離と椅子の速度
  - データ: 椅子の速度は `chair_models.speed`。`chairs.model` と `chair_models.name` が対応する。椅子の現在地は、`chair_locations` の最新行
  - ベンチ: 迎車の満足は、迎車距離が `10 × 椅子の速度` 未満（「ライド」の評価）。速い椅子は、遠い乗車位置でも満足を取れる

### 決済マイクロサービス

- 決済サーバーエンドポイントの設定
  - 処理: `POST /api/initialize` のボディ `{"payment_server": "<URL>"}`（`webapp/ruby/lib/isuride/initialize_handler.rb`）
  - 処理: 手元のモックは `http://localhost:12345`（`isuride-payment_mock.service`）
  - ベンチ: 本番のベンチは決済サーバーを自分で立て、走行のたびに `/api/initialize` でその URL を渡す。ログ先頭の `paymentURL=<URL>`（例: `http://172.31.9.63:12346`）
  - ベンチ: この宛先に決済しないと `CODE=34`（決済が届かない）、決済の内容が誤っていると `CODE=35`（誤った支払い）
