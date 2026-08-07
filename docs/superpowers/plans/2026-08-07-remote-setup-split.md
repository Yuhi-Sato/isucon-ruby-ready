# remote-setup.sh分離とセットアップ再開性 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `setup.sh`のサーバー側処理を単体実行可能・冪等な`remote-setup.sh`に分離し、SSHユーザーが`isucon`でない環境でも自動sudoで通るようにする。

**Architecture:** `setup.sh`内の`REMOTE_SCRIPT`ヒアドキュメントをリポジトリ直下の`remote-setup.sh`へ移設し、`ssh ... bash -s -- <args> < remote-setup.sh`で流し込む。`setup.sh`は接続ユーザーを`whoami`で確認し、`isucon`でなければサーバー側2フェーズ（Deploy key生成・remote-setup実行）を`sudo -n -u isucon -H bash -s`でラップする。`remote-setup.sh`は鍵の自己修復と認証失敗時の復旧案内を持ち、`sudo -i -u isucon`後の単体実行で途中から再開できる。

**Tech Stack:** bash / ssh / git / gh CLI（ローカルのみ）/ curl / tar

**Spec:** [docs/superpowers/specs/2026-08-07-remote-setup-split-design.md](../specs/2026-08-07-remote-setup-split-design.md)

## Global Constraints

- 両スクリプトともbash前提（`#!/bin/bash`、`set -euo pipefail`）。`server-setup.sh`のみdash互換（既存のまま、変更しない）
- `REPO_OWNER`は`Yuhi-Sato`固定。鍵ファイル名は`github_deploy_<repo-name>`、SSH URLは`git@github.com:Yuhi-Sato/<repo-name>.git`（`setup.sh`と`remote-setup.sh`で同一の導出）
- `isucon`直接続の従来フローの挙動を変えない（sudoラップは接続ユーザーが`isucon`でないときのみ）
- コメント・メッセージは既存スクリプトに合わせて日本語
- 自動テスト基盤は無い。各タスクの検証は`bash -n`・`shellcheck`（あれば）・ローカルで安全に実行できる引数バリデーション確認で行う。実サーバーでの通し検証はプラン外（練習用EC2で手動）

**sudoフラグについての補足（スペックからの意図的変更）:** スペックは`sudo -iu isucon`と書いているが、実装は`sudo -n -u isucon -H`を使う。理由: (1) `-i`はログインシェルとして`.profile`/`.bashrc`を読むため、rbenv等の出力が`PUB_KEY`のキャプチャを汚染しうる。`-H`なら`$HOME`だけをisuconのものに差し替えられる。(2) `-n`でパスワードが必要な環境では即失敗し、stdin（流し込み中のスクリプト）をsudoのパスワードプロンプトに横取りされる事故を防ぐ。Task 2でスペック側の記述も合わせて修正する。

---

### Task 1: `remote-setup.sh`の新規作成

**Files:**
- Create: `remote-setup.sh`（リポジトリ直下、実行権付き）

**Interfaces:**
- Consumes: `server-setup.sh <s1|s2|s3>`（既存・変更なし）
- Produces: `bash remote-setup.sh <s1|s2|s3> <repo-name> [--dir <path>]`。stdinから`bash -s -- <args>`で流し込んでも、ファイルとして直接実行しても動く。Task 2の`setup.sh`がこのインターフェースを呼ぶ

- [ ] **Step 1: `remote-setup.sh`を作成する**

以下の内容で作成する。git配線ロジックは現行`setup.sh`のヒアドキュメント（s1とs2/s3でほぼ重複している部分）を`setup_git_remote`関数に統合して移設したもの。

```bash
#!/bin/bash

# サーバー上で実行するセットアップスクリプト（tarball展開〜チームリポジトリのgit配線）。
# 通常は setup.sh がローカルから `ssh ... bash -s -- <args> < remote-setup.sh` で流し込む。
#
# setup.sh が使えない・途中で失敗した場合（tar展開の権限エラー等）は、サーバー上で
# isuconユーザーとして（isuconでないユーザーなら sudo -i -u isucon した状態で）
# 単体実行して途中から再開できる:
#
#   curl -fsSL https://raw.githubusercontent.com/Yuhi-Sato/isucon-ruby-ready/main/remote-setup.sh \
#     | bash -s -- s1 <repo-name>
#
# 何度実行しても安全（冪等）。Deploy keyが未登録の場合は復旧手順を表示して終了する。

set -euo pipefail

REPO_OWNER="Yuhi-Sato"
DEFAULT_TARGET_DIR="/home/isucon"

usage() {
  echo "Usage: $0 <s1|s2|s3> <repo-name> [--dir <path>]" >&2
  echo "  s1   : tarball展開〜チームリポジトリへの初回pushまで行う" >&2
  echo "  s2/s3: チームリポジトリの取得とセットアップを行う" >&2
  echo "  --dir: 配布リポジトリのルート（webapp/と同階層）。省略時は ${DEFAULT_TARGET_DIR}" >&2
  exit 1
}

TARGET_DIR="$DEFAULT_TARGET_DIR"
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      [ "$#" -ge 2 ] || usage
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  usage
fi

ROLE="${POSITIONAL[0]}"
REPO_NAME="${POSITIONAL[1]}"

if ! echo "$ROLE" | grep -qE '^s[1-3]$'; then
  echo "エラー: 役割は s1 / s2 / s3 のいずれかで指定してください（指定値: ${ROLE}）" >&2
  usage
fi

# setup.shと同じ導出（単体実行時の引数を最小にするため、ここでも導出する）
REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
REPO_SSH_URL="git@github.com:${REPO_SLUG}.git"
KEY_BASENAME="github_deploy_${REPO_NAME}"
KEY_FILE="$HOME/.ssh/$KEY_BASENAME"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"

# このリポジトリ専用のDeploy keyだけを使う（agentや他の鍵に依存しない）
GIT_SSH_CMD="ssh -i $KEY_FILE -o IdentitiesOnly=yes"
export GIT_SSH_COMMAND="$GIT_SSH_CMD"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Deploy keyの自己修復: setup.shがisucon以外のユーザーで失敗した後は、鍵が
# そのユーザーのhomeにしか無いことがある。実行ユーザーのhomeに無ければ生成する。
if [ ! -f "$KEY_FILE" ]; then
  echo "Deploy key (${KEY_FILE}) が無いため生成します..."
  # </dev/null: bash -s（stdin経由）で実行された場合に、stdinを読みうる子プロセスが
  # 残りのスクリプトを横取りするのを防ぐ
  ssh-keygen -q -t ed25519 -N "" -f "$KEY_FILE" -C "${ROLE}-${KEY_BASENAME}" </dev/null
fi

# github.comのホストキーがknown_hostsになければssh-keyscanで追加する
if ! ssh-keygen -F github.com -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "github.comのホストキーが未登録のため追加します..."
  ssh-keyscan -H github.com >> "$KNOWN_HOSTS" 2>/dev/null
fi

# Deploy keyでのGitHub認証疎通確認
# </dev/null必須: bash -s（stdin経由）実行時、stdinを切らないとこのssh -Tが
# 残りのスクリプトを横取りし、エラーも出さずここで静かに終了してしまう。
AUTH_CHECK="$(ssh -i "$KEY_FILE" -o IdentitiesOnly=yes -T git@github.com </dev/null 2>&1 || true)"
if ! echo "$AUTH_CHECK" | grep -q "successfully authenticated"; then
  echo "エラー: Deploy keyでのGitHubへのSSH認証に失敗しました。" >&2
  echo "以下の公開鍵を ${REPO_SLUG} のDeploy keyとして登録してから、このスクリプトを再実行してください。" >&2
  echo "" >&2
  cat "$KEY_FILE.pub" >&2
  echo "" >&2
  echo "ローカルでの登録コマンド例（上記公開鍵を deploy_key.pub として保存した上で）:" >&2
  echo "  gh repo deploy-key add deploy_key.pub --repo ${REPO_SLUG} --allow-write --title ${ROLE}" >&2
  echo "" >&2
  echo "sshの応答:" >&2
  echo "$AUTH_CHECK" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# git init・origin設定・Deploy keyのcore.sshCommand固定（s1/s2/s3共通・冪等）
setup_git_remote() {
  if [ ! -d .git ]; then
    git init -b main
  else
    echo ".gitは既に初期化済みのため、git initをスキップします。"
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    if [ "$(git remote get-url origin)" != "$REPO_SSH_URL" ]; then
      git remote set-url origin "$REPO_SSH_URL"
    fi
  else
    git remote add origin "$REPO_SSH_URL"
  fi

  # 以後の git pull / push（make deploy / make bench 含む）が追加設定なしで
  # このDeploy keyを使うよう、リポジトリ設定に固定する
  git config core.sshCommand "$GIT_SSH_CMD"
}

if [ "$ROLE" = "s1" ]; then
  # ISUCON運営配布リポジトリのルート（webapp/と同階層）に、このリポジトリの
  # ツール一式を展開する（既に展開済みでも上書きになるだけで冪等）。
  echo "isucon-ruby-readyのツール一式を展開します..."
  curl -fsSL https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
    | tar xz --strip-components=1

  # ツール導入・ディレクトリ準備・サーバー設定取得（env.sh作成 → make setup →
  # make set-as-s1 → make get-conf）。get-confの結果（s1/etc/配下）を
  # このあとの初回コミットに含める。
  sh server-setup.sh s1

  setup_git_remote

  git add .
  if git diff --cached --quiet; then
    echo "コミット対象の変更がないため、コミットをスキップします。"
  else
    git commit -m 'first commit'
  fi

  if ! git push -u origin main; then
    echo "エラー: git pushに失敗しました。" >&2
    echo "Deploy keyが書き込み権限付き（--allow-write）で登録されているかを確認してから再実行してください。" >&2
    exit 1
  fi
else
  # s2/s3: TARGET_DIRにはISUCON運営配布のアプリコード（webapp/等）が既に
  # 展開された状態で置かれている（非空）。git cloneは非空ディレクトリを
  # 拒否するため使えず、代わりにgit init + fetch + checkoutでチーム
  # リポジトリの内容（Makefile・tool-config・webapp含む）を被せる。
  setup_git_remote

  echo "チームリポジトリ (${REPO_SSH_URL}) からmainを取得します..."
  git fetch origin main
  git checkout -f -B main origin/main

  # ツール導入・ディレクトリ準備・サーバー設定取得（env.sh作成 → make setup →
  # make set-as-s2/s3 → make get-conf）。
  sh server-setup.sh "$ROLE"
fi

echo "サーバー側のセットアップが完了しました（role: ${ROLE}）。"
```

- [ ] **Step 2: 実行権を付ける**

```bash
chmod +x remote-setup.sh
```

- [ ] **Step 3: 構文チェック**

Run: `bash -n remote-setup.sh`
Expected: 出力なし（exit 0）

Run: `command -v shellcheck >/dev/null && shellcheck remote-setup.sh || echo "shellcheck未導入のためスキップ"`
Expected: エラーなし（info/style指摘のみなら許容。SC2086等のwarning以上が出たら修正する）

- [ ] **Step 4: 引数バリデーションの動作確認（ローカルで安全に実行できる範囲）**

以下はいずれもサーバー操作に到達する前に終了するため、ローカルで実行して安全:

Run: `bash remote-setup.sh; echo "exit=$?"`
Expected: Usageが表示され `exit=1`

Run: `bash remote-setup.sh s4 myrepo; echo "exit=$?"`
Expected: 「エラー: 役割は s1 / s2 / s3 ...」とUsageが表示され `exit=1`

Run: `bash remote-setup.sh s1; echo "exit=$?"`
Expected: Usageが表示され `exit=1`（repo-name不足）

- [ ] **Step 5: Commit**

```bash
git add remote-setup.sh
git commit -m "feat(setup): add standalone idempotent remote-setup.sh

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `setup.sh`の改修（remote-setup.sh呼び出し＋自動sudo）

**Files:**
- Modify: `setup.sh`（ヒアドキュメント`REMOTE_SCRIPT`の置き換え、whoami確認とsudoラップの追加、pubkeyキャプチャの頑健化）
- Modify: `docs/superpowers/specs/2026-08-07-remote-setup-split-design.md`（sudoフラグの記述を実装に合わせる）

**Interfaces:**
- Consumes: Task 1の`remote-setup.sh <s1|s2|s3> <repo-name> [--dir <path>]`（stdin流し込み）
- Produces: `./setup.sh <user@server> [repo-name] [--dir <path>] [--role <s1|s2|s3>]`（外部インターフェースは変更なし）

- [ ] **Step 1: サーバー側実行ユーザーの決定ブロックを追加する**

`setup.sh`の`# --- Deploy keyの生成（サーバー上）と登録（ローカルのgh CLI） ---`セクションの直前（リポジトリ作成/存在確認セクションの後）に以下を挿入する:

```bash
# --- サーバー側処理の実行ユーザーの決定 ---
# 練習環境等ではSSH接続ユーザーがisuconでない（ubuntu等の管理ユーザー）ことがある。
# そのままでは/home/isuconへのtar展開が権限エラーになり、Deploy keyも接続ユーザーの
# homeに作られてisuconのgit操作と噛み合わない。接続ユーザーがisuconでなければ、
# サーバー側処理（鍵生成・remote-setup.sh）全体をsudoでisuconとして実行する。
# -n: パスワードが必要ならプロンプトで固まらず即失敗させる（passwordless sudo前提）
# -H: $HOMEをisuconのものにする。-i（ログインシェル）は使わない。.profile等の
#     出力が後続のpubkeyキャプチャを汚染しうるため。
REMOTE_USER="$(ssh -o RemoteCommand=none "$SERVER" whoami)"
REMOTE_BASH=(bash -s)
if [ "$REMOTE_USER" != "isucon" ]; then
  echo "SSH接続ユーザーが ${REMOTE_USER} のため、サーバー側処理は sudo -u isucon で実行します。"
  REMOTE_BASH=(sudo -n -u isucon -H bash -s)
fi
```

- [ ] **Step 2: Deploy key生成フェーズをsudo対応にし、pubkeyキャプチャを頑健化する**

keygen呼び出し行（現行130行目付近）:

```bash
PUB_KEY="$(ssh -o RemoteCommand=none "$SERVER" bash -s -- "$KEY_BASENAME" "$ROLE" <<'KEYGEN_SCRIPT'
```

を以下に変更する（ヒアドキュメント`KEYGEN_SCRIPT`の中身は変更しない）:

```bash
PUB_KEY_RAW="$(ssh -o RemoteCommand=none "$SERVER" "${REMOTE_BASH[@]}" -- "$KEY_BASENAME" "$ROLE" <<'KEYGEN_SCRIPT'
```

続けて、ヒアドキュメント終了直後の検証ブロック（現行146〜150行目）:

```bash
if ! echo "$PUB_KEY" | grep -q "^ssh-ed25519 "; then
  echo "エラー: サーバー上でのDeploy key生成に失敗しました。" >&2
  echo "$PUB_KEY" >&2
  exit 1
fi
```

を以下に置き換える:

```bash
# sudo経由等で余計な出力が混ざる可能性に備え、公開鍵の行だけを取り出す
PUB_KEY="$(echo "$PUB_KEY_RAW" | grep '^ssh-ed25519 ' | tail -n 1 || true)"

if [ -z "$PUB_KEY" ]; then
  echo "エラー: サーバー上でのDeploy key生成に失敗しました。" >&2
  echo "$PUB_KEY_RAW" >&2
  echo "（sudoのパスワードが要求される環境の場合は、READMEのフォールバック手順でremote-setup.shを直接実行してください）" >&2
  exit 1
fi
```

- [ ] **Step 3: `REMOTE_SCRIPT`ヒアドキュメントを`remote-setup.sh`の流し込みに置き換える**

`# --- サーバー側処理（1回のSSH接続に集約する） ---`から`REMOTE_SCRIPT`終端（現行169〜288行目）までを丸ごと以下に置き換える:

```bash
# --- サーバー側処理（remote-setup.shを流し込んで実行する） ---
# 中身はremote-setup.sh参照。サーバー上で単体実行して再開することもできる。

echo "サーバー ${SERVER} 上でセットアップを行います..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ssh -o RemoteCommand=none "$SERVER" "${REMOTE_BASH[@]}" -- "$ROLE" "$REPO_NAME" --dir "$TARGET_DIR" \
  < "$SCRIPT_DIR/remote-setup.sh"
```

注意: `REPO_SSH_URL`・`KEY_BASENAME`の導出（現行82〜88行目）は、keygenフェーズと最終メッセージが使うため`setup.sh`にも残す（`remote-setup.sh`と重複するが許容。スペック参照）。

- [ ] **Step 4: 構文チェックとローカルでの動作確認**

Run: `bash -n setup.sh`
Expected: 出力なし（exit 0）

Run: `command -v shellcheck >/dev/null && shellcheck setup.sh || echo "shellcheck未導入のためスキップ"`
Expected: エラーなし（warning以上が出たら修正する）

Run: `./setup.sh; echo "exit=$?"`
Expected: Usageが表示され `exit=1`（引数なし・SSHに到達しない）

Run: `./setup.sh s2; echo "exit=$?"`
Expected: 「エラー: role=s2 の場合はrepo-nameの指定が必須です...」で `exit=1`

- [ ] **Step 5: スペックのsudoフラグ記述を実装に合わせて修正する**

`docs/superpowers/specs/2026-08-07-remote-setup-split-design.md`の設計方針3にある`sudo -iu isucon bash -s`（2箇所: 見出し下の本文と「データフロー」節）を`sudo -n -u isucon -H bash -s`に置き換え、本文側に理由を1文追記する:

```
- `-n`はパスワード要求時に即失敗させるため、`-H`は`$HOME`をisuconに差し替えるため。`-i`（ログインシェル）は`.profile`等の出力がpubkeyキャプチャを汚染しうるため使わない
```

（既存の「`sudo -i`により`$HOME`・カレントが...」の行はこの内容で置き換える）

- [ ] **Step 6: Commit**

```bash
git add setup.sh docs/superpowers/specs/2026-08-07-remote-setup-split-design.md
git commit -m "feat(setup): pipe remote-setup.sh over ssh and auto-sudo to isucon

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: READMEのフォールバック節更新

**Files:**
- Modify: `README.md`（「ローカル経由が使えない場合のフォールバック」節の書き換え、setup.sh説明への自動sudo追記）

**Interfaces:**
- Consumes: Task 1の`remote-setup.sh`のraw URLワンライナー、Task 2の自動sudo挙動
- Produces: ドキュメントのみ

- [ ] **Step 1: setup.sh説明に自動sudoの挙動を追記する**

README「かつてのssh agent forwarding...」の段落の直前（`gh auth login`の説明段落の直後）に以下の1段落を追加する:

```markdown
SSH接続ユーザーが`isucon`でない場合（練習環境等で`ubuntu`等の管理ユーザーで接続する構成）は、`setup.sh`がサーバー側処理を自動で`sudo -u isucon`として実行する（passwordless sudo前提）。これによりDeploy keyも必ず`isucon`のhomeに作られる。
```

- [ ] **Step 2: フォールバック節を書き換える**

現行の節:

````markdown
### ローカル経由が使えない場合のフォールバック

`gh`が使えないなど、ローカルからの1コマンドが使えない場合は、サーバーに直接SSHして手動で行う。

```bash
# サーバー上（配布リポジトリのルートで）
curl -L https://github.com/Yuhi-Sato/isucon-ruby-ready/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=1
sh server-setup.sh s1   # s2/s3の場合は s2 / s3
```

この場合、チームリポジトリへのgit初期化・push（s1）やgit配線（s2/s3）、Deploy keyの生成・登録は別途手動で行う必要がある。
````

を以下に置き換える:

````markdown
### ローカル経由が使えない場合のフォールバック / 途中失敗からの再開

`gh`が使えない、または`setup.sh`がtar展開の権限エラー等で途中失敗した場合は、サーバー上で**isuconユーザーとして**`remote-setup.sh`を単体実行する。tarball展開・`server-setup.sh`・git配線（s1は初回push、s2/s3はfetch/checkout）までこれ1本で行い、何度実行しても安全（冪等）。

```bash
# サーバー上。isuconユーザーでない場合は先に sudo -i -u isucon する
curl -fsSL https://raw.githubusercontent.com/Yuhi-Sato/isucon-ruby-ready/main/remote-setup.sh \
  | bash -s -- s1 <repo-name>   # s2/s3の場合は s2 / s3。ルートが異なる場合は --dir <path> を追加
```

Deploy keyが未登録（または実行ユーザーのhomeに鍵が無い）場合は、鍵を生成したうえで公開鍵とローカルで実行すべき`gh repo deploy-key add`コマンドを表示して止まるので、登録してから再実行すると続きから進む。
````

- [ ] **Step 3: 表記の整合確認**

Run: `grep -n "remote-setup" README.md setup.sh`
Expected: READMEのフォールバック節とsetup.shの流し込み箇所がヒットする

Run: `grep -n "server-setup.sh s1" README.md`
Expected: 旧フォールバックの`sh server-setup.sh s1`直書きが（server-setup.sh自体の説明を除き）残っていないことを確認する

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): document remote-setup.sh fallback and auto-sudo

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
