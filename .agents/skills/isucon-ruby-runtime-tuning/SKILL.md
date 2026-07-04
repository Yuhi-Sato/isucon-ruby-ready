---
name: isucon-ruby-runtime-tuning
description: ISUCONのRuby実装でYJIT有効化やGC設定など、コード変更なしで効くRubyランタイムのチューニングを行うときに使う。「YJITを有効にして」「GCをチューニングして」「Rubyを高速化したい」「コードを変えずに速くしたい」などのリクエストで使用する。
---

# ISUCON Rubyランタイムチューニング

## 概要

アプリコードを一切変えずに、起動オプション・環境変数だけで効くチューニング。
N+1解消やインデックス追加（isucon-optimization-patterns）ほどの効果は無いことが多いが、
**適用コストがほぼゼロ**なので、初動調査の直後や大きな改善の合間に試す価値がある。

適用は必ず systemdユニットの起動コマンドか、Gemfile経由。**サーバー上で直接プロセスを再起動して試すのではなく、
必ず設定として残す**（再起動試験で消えると再現できない）。

## 前提確認

```bash
ssh s1 "ruby -v"
```

- **YJITはRuby 3.2以降が必要**（3.1以前は `--yjit` オプション自体が無い）。問題のRubyバージョンを最初に確認する
- Ruby 3.3以降はYJITのウォームアップが速く、短時間のベンチでも効果が出やすい。3.2はベンチ時間が短いと恩恵が薄いことがある
- **3.1以前でYJITが使えない場合**、このスキルの他の手（GCチューニング）や `isucon-puma-tuning` の構成調整に進む。YJIT自体はスキップするだけで、他のランタイムチューニングの適用可否には影響しない

## 1. YJIT有効化

最もコストが低く、ほぼ確実にプラスに働く。**まずこれを試す。**

```bash
# 環境変数で有効化（Gemfile/コード変更不要）
RUBY_YJIT_ENABLE=1
```

systemdユニットの `[Service]` セクションに追加するか、`env.sh` に追記してアプリ起動スクリプトが読み込むようにする。

```ini
# /etc/systemd/system/<SERVICE_NAME>.service の [Service] セクション
Environment=RUBY_YJIT_ENABLE=1
```

systemdユニットは `make get-conf` の管理対象外なので直接編集してよい（isucon-server-tuning参照）。変更後は
`sudo systemctl daemon-reload && sudo systemctl restart <SERVICE_NAME>` を忘れないこと。

適用後、`ps` や起動ログで有効化を確認する:

```bash
ruby -e 'puts RubyVM::YJIT.enabled?'   # true になっているか
```

## 2. GCチューニング

デフォルトのGCヒープ拡張はISUCONのような短時間高負荷ワークロードでは頻繁にGCが走りやすい。
**計測シグナル**: `GC.stat` の `:count`（GC回数）がベンチ実行時間に対して多い、または `:major_gc_count` が
リクエスト処理中に複数回発生している場合に適用対象とする（目安: ベンチ1回=数十秒で数百回以上GCが走っていれば
ヒープ拡張が追いついていない可能性が高い）。

```bash
# 環境変数（コード変更不要）
RUBY_GC_HEAP_INIT_SLOTS=1000000
RUBY_GC_HEAP_GROWTH_FACTOR=1.8
RUBY_GC_MALLOC_LIMIT=90000000
```

- `RUBY_GC_HEAP_INIT_SLOTS`: 初期ヒープを大きめに確保し、起動直後のヒープ拡張（GC発生）を減らす
- 値は環境のメモリと相談する。**盛りすぎるとメモリ不足でOOM Killerに殺される**ため、`free -h` で確認しながら調整する

## 3. Pumaのワーカー/スレッド構成

Puma固有の調整（workers数、threads数、preload_app等）は `isucon-puma-tuning` スキルを参照。
YJIT/GCと違い、アプリの並行処理特性（GVL・I/O待ちの多さ）を踏まえた判断が必要なため別スキルとして扱う。

## 適用順序の目安

1. YJIT有効化（コスト最小・効果はほぼプラスのみ）
2. GC調整（計測してヒープ拡張が多い場合のみ）
3. Pumaワーカー/スレッド構成（isucon-puma-tuning へ）

## よくある失敗

| 失敗 | 対策 |
|---|---|
| Ruby 3.1以前でYJITを有効化しようとしてエラー | 最初に `ruby -v` を確認する |
| サーバーで直接環境変数をexportして試し、再起動試験で消える | systemdユニット or env.sh に恒久設定として書く |
| GCヒープを盛りすぎてOOM Killerに殺される | `free -h` で実メモリを確認しながら段階的に増やす |
| 効果を計測せず「定番だから」と全部一度に入れる | 1設定→1ベンチで効果を確認する（isucon-bottleneck-analysis参照） |
