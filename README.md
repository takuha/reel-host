# reel-host

リールを投稿して、見た人に DM を返すための一式。役割が4つに分かれている。

| スクリプト | 役割 |
| --- | --- |
| `reel_fetch.sh` | TikTok などの共有URLから動画の元ファイルを取ってくる |
| `reel_host.sh` | 動画を GitHub Pages に載せて公開URLを出す／投稿後に消す |
| `reel_post.sh` | その公開URLを Meta Graph API に渡してリールとして投稿する |
| `reel_dm.sh` | 投稿に来たコメントを拾って、その人に DM を送る |
| `cleanup.sh` | 消し忘れた動画を時間経過で拾う保険（毎朝9時に自動実行） |

Meta Graph API は動画を「公開URLから取得」する方式なので、投稿する前にどこかに
公開しておく必要がある。その置き場がこのリポジトリ。

## 準備

```sh
cp .env.example .env   # .env は .gitignore 済み。git には乗らない。
```

`.env` にアカウントごとのトークンと IG ユーザー ID を書く。**接頭辞がそのまま
アカウント名になる**（`AOYAGI_` → `aoyagi`）。

```
AOYAGI_IG_USER_ID=17841400000000000
AOYAGI_ACCESS_TOKEN=EAAG...
```

### トークンと IG ユーザー ID の取り方

アカウントを1つ増やすたびに、この手順を通す必要がある。**トークンは認可したアカウント
にしか使えない**ので、既存アカウントのトークンを流用することはできない。

1. 増やすアカウントを **プロアカウント**（ビジネスまたはクリエイター）にする。
   個人アカウントのままでは投稿APIの対象外。
2. そのアカウントを Facebook ページと連携し、ページをアプリと同じ
   ビジネスポートフォリオに入れる。
3. Graph API Explorer でアプリを選び、次の権限を付けてトークンを生成する。
   このとき**増やすアカウントのページにチェックを入れる**こと。

   ```
   instagram_basic  instagram_content_publish
   instagram_manage_comments  instagram_manage_messages
   pages_show_list  pages_read_engagement  business_management
   ```

   下2つは DM 用。投稿だけなら要らないが、後から足すにはトークンを取り直す
   ことになるので最初から付けておく。

4. 生成したトークンで IG ユーザー ID を引く。ここで出た `id` が `_IG_USER_ID`。

   ```
   me/accounts?fields=name,instagram_business_account{id,username}
   ```

5. `.env` に書いて、長期トークンに延長する（次項）。

### トークンの延長

Explorer が出すトークンは**1時間で切れる**。そのままだと翌日にはまた
「接続できない」状態に戻るので、長期（60日）に延長しておく。

```sh
./reel_post.sh refresh aoyagi
```

`.env` を書き換えて、元の内容を `.env.bak` に残す。失敗したときは `.env` に触らない。
Facebook ログイン方式では `META_APP_ID` と `META_APP_SECRET` が必要（アプリの
設定 → ベーシックにある）。60日ごとに打ち直せば切れない。

## 使い方

```sh
./reel_post.sh accounts                                   # 設定済みアカウント
./reel_post.sh check aoyagi                               # 接続確認
./reel_post.sh refresh aoyagi                             # トークンを60日に延長
./reel_post.sh publish aoyagi ~/Movies/reel001.mp4 "本文" # 公開→投稿→後片付け
```

`publish` は「ホスティング → 投稿 → 投稿できた分だけ削除」までやる。まだ投稿して
いない動画は消さない。

個別にやるなら:

```sh
./reel_host.sh add aoyagi ~/Movies/reel001.mp4   # 公開して URL を出す
./reel_post.sh post aoyagi "<url>" "本文"        # その URL を投稿する
./reel_host.sh clean aoyagi reel001.mp4          # 1本だけ消す
./reel_host.sh clean aoyagi                      # そのアカウント分を全部消す
```

`add` は GitHub Pages が実際に配信を始めるまで待ってから URL を出す。プッシュ直後は
まだ 404 で、待たずに Graph API へ渡すと動画取得に失敗するため。

## URL から投稿する

`publish` と `add` は、動画ファイルの代わりに**動画のURLをそのまま渡せる**。手元に
ダウンロードしてからパスを打つ、という手間が要らない。

```sh
./reel_post.sh publish aoyagi https://vt.tiktok.com/XXXXXXXX/ "本文"
```

TikTok などの共有URLは「ページのURL」であって動画そのものではないので、ページを
解析して実体を取り出す必要がある。そこは `yt-dlp` に任せている。**URL を渡す使い方を
するなら `yt-dlp` を入れておくこと。**

```sh
brew install yt-dlp     # または pipx install yt-dlp
```

URL が直接 `.mp4` を指している場合は `curl` だけで取れるので `yt-dlp` は要らない。

取ってくるだけなら単体でも使える。出力先を省略すると一時ディレクトリに置く。

```sh
./reel_fetch.sh https://vt.tiktok.com/XXXXXXXX/            # パスを出す
./reel_fetch.sh https://vt.tiktok.com/XXXXXXXX/ ~/Movies   # 置き場所を指定
```

### ログインが要る動画

非公開・年齢制限などでログインが必要な動画は、Cookie を渡さないと取れない。
**ブラウザでログインしているだけでは効かない**（スクリプトはそのブラウザとは別物
なので、ログイン状態を引き継がない）。

```sh
REEL_FETCH_COOKIES_FROM_BROWSER=chrome ./reel_post.sh publish aoyagi "<url>" "本文"
```

エクスポート済みの Cookie ファイル（Netscape 形式）があるならこちら。

```sh
REEL_FETCH_COOKIES=~/cookies.txt ./reel_post.sh publish aoyagi "<url>" "本文"
```

なお、他人の動画をそのまま投稿してよいかは別の話。権利は自分で確認すること。

### 投稿できるURLとできないURL

`post` に渡す `<url>` と、`publish` / `add` に渡す `<url>` は別物なので注意。

| コマンド | 渡すURL |
| --- | --- |
| `publish` / `add` | 動画の**取得元**。TikTok の共有URLなど。手元に落としてから載せ直す |
| `post` | **自分で公開したURL**。`add` が出したもの。Meta がここから動画を取りに来る |

`post` に TikTok のURLを直接渡しても通らない。Meta は渡されたURLから動画ファイル
そのものを取得しようとするので、ページのURLでは失敗する。

## DM を送る

**面識のない相手に API から DM を送ることはできない。** 送れるのは次の2つだけ。

1. **コメントへの返信** — リールに来たコメント1件につき1回だけ、その相手に DM を
   送れる。コメントから7日以内。新規の相手に届く入口はこれしかない。
2. **相手から DM が来ている場合** — 相手の最後のメッセージから24時間以内なら返せる。

つまり順番が決まっている。**先にリールを出し、コメントをもらってから DM**であって、
DM だけ先に送っておくことはできない。「コメントしたら送ります」と本文に書いて
コメントを集めるのが 1 の使い方。

```sh
./reel_dm.sh check aoyagi          # DM が送れる状態か確かめる
./reel_dm.sh media aoyagi          # 直近の投稿を出して media-id を拾う
./reel_dm.sh comments aoyagi 17912345 --match 受け取り   # 誰が来ているか見る
./reel_dm.sh sweep aoyagi 17912345 "本文" --match 受け取り          # 下見
./reel_dm.sh sweep aoyagi 17912345 "本文" --match 受け取り --send   # 送る
```

`sweep` は **`--send` を付けるまで送らない**。まず付けずに打って、宛先と本文を
確認してから付け直す。`--match` を付けると、その文字列を含むコメントだけに絞れる。

1件ずつやるなら:

```sh
./reel_dm.sh reply aoyagi <comment-id> "本文"   # コメント主に送る
./reel_dm.sh threads aoyagi                     # DM が来ている相手を出す
./reel_dm.sh send aoyagi <igsid> "本文"         # 24時間以内の相手に返す
```

送った相手は `.dm_sent/<account>.log` に残る（`.gitignore` 済み）。`sweep` はここに
ある相手を自動で飛ばすので、同じ人に二度送らない。`comments` の `*` が送信済み。

本文のたたき台は [`dm_templates.md`](dm_templates.md)。一通目にリンクを入れるかで
その後が変わる（入れずに返信をもらうと24時間の窓が開いて続きを送れる）ので、
文面より先にそこを決めること。

送信中に1件失敗しても残りは送る。理由は相手ごとに違う（7日超過、返信済みなど）ので、
失敗した分だけエラーが出る。

### DM だけ通らないとき

投稿用と DM 用は**別の権限**なので、`reel_post.sh check` が通っていても DM は落ちる。
`reel_dm.sh check` を打つと、どちらの権限が欠けているかが出る。

```
$ ./reel_dm.sh check aoyagi
接続OK: aoyagi → @aoyagi_shop (17841400000000000)
権限が足りない: instagram_manage_messages
```

足りない場合はトークンを取り直すしかない。Graph API Explorer で
`instagram_manage_messages` と `instagram_manage_comments` にチェックを入れて生成し、
`.env` に書いて `./reel_post.sh refresh aoyagi` で60日に延長する。

## 消し忘れの保険

`clean` を打ち忘れた分は `cleanup.sh` が拾う。コミットから3日以上経った動画を削除して
push するだけのスクリプトで、毎朝9時に自動実行される。

```sh
./cleanup.sh --dry-run        # 対象を確認するだけ
RETENTION_DAYS=7 ./cleanup.sh # 保持期間を変える
```

`videos/<account>/` に置いた動画もそのまま対象になる。

## つながらないとき

まず `check` を打つ。エラーの内容と、**そのトークンで実際に使えるアカウントの一覧**が
出るので、原因はほぼここで分かる。

```
$ ./reel_post.sh check aoyagi
reel_post: aoyagi への接続確認 に失敗
  message          Unsupported get request. Object with ID '999' does not exist
  code             100

このトークンで使えるアカウント:
  たくは商店: @takuha_shop 111
```

一覧に目的のアカウントが出てこない場合、原因は次のどれか。

1. **トークンがそのアカウントに未認可** — トークンは認可したアカウントにしか使えない。
   アカウントを増やしたら認可をやり直し、そのアカウント自身の IG ユーザー ID を取り直す。
2. **プロアカウントになっていない** — 個人アカウントは投稿APIの対象外。
   ビジネスまたはクリエイターに切り替える。
3. **Facebook ページと未連携** — Facebook ログイン方式の場合のみ必要。
4. **アプリが開発モード** — アプリにロールを持つ人のアカウントしか通らない。
5. **ビジネスポートフォリオが別** — アプリとアカウントが同じポートフォリオにいない。

一覧そのものが取れない場合は、トークン自体が無効か期限切れ。`code 190` が出ていたら
期限切れなので、トークンを取り直して `refresh` で延長する。

## アカウントを増やす

`.env` に2行足すだけ。スクリプト側の変更は要らない。動画も `videos/<account>/` に
自動で分かれる。

```
videos/aoyagi/reel001.mp4
  → https://takuha.github.io/reel-host/videos/aoyagi/reel001.mp4
```

## 設定

環境変数で上書きできる。

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `REEL_HOST_BASE_URL` | `https://takuha.github.io/reel-host` | 公開URLの先頭 |
| `REEL_HOST_BRANCH` | `main` | GitHub Pages の配信元ブランチ |
| `REEL_HOST_WAIT_TRIES` / `_INTERVAL` | `30` / `5` | 公開されるまでの確認回数・間隔（秒） |
| `REEL_GRAPH_HOST` | `graph.facebook.com` | Instagram ログイン方式なら `graph.instagram.com` |
| `REEL_GRAPH_VERSION` | `v21.0` | Graph API のバージョン |
| `REEL_POLL_TRIES` / `_INTERVAL` | `60` / `5` | 動画変換を待つ回数・間隔（秒） |
| `REEL_DM_INTERVAL` | `2` | `sweep` で1件送るごとに空ける秒数 |
| `REEL_DM_LOG_DIR` | `./.dm_sent` | DM の送信台帳の置き場 |
| `REEL_ENV_FILE` | `./.env` | 設定ファイルの場所 |
| `REEL_FETCH_COOKIES` | なし | URL取得に使う Cookie ファイル（Netscape 形式） |
| `REEL_FETCH_COOKIES_FROM_BROWSER` | なし | Cookie をブラウザから直接読む（`chrome` など） |

`REEL_GRAPH_VERSION` はバージョン切れを言われたら上げる。既定値が現時点の最新とは
限らないので、エラーが出たら Meta の changelog で確認すること。

必要なコマンドは `curl` と、`jq` または `python3` のどちらか。URL から投稿するなら
これに `yt-dlp` が加わる。

## Claude Code で使う

`.mcp.json` と `.claude/skills/` を同梱してある。このリポジトリを開けばそのまま効く。

| 入っているもの | 用途 |
| --- | --- |
| `reel-caption` スキル | 投稿の本文を書く／AIっぽい文章を直す |
| Context7 (MCP) | Meta Graph API の最新ドキュメントを引く |
| GitHub MCP | PR・Actions・Pages の状態を見る |

`REEL_GRAPH_VERSION` のバージョン切れは Context7 に Graph API の最新版を引かせると早い。

MCP は環境変数を読む。使う前にシェルへ入れておく（`.env` とは別。トークンの性質が違う）。

```sh
export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_...   # GitHub MCP に必要
export CONTEXT7_API_KEY=...                   # 無くても動く。入れるとレート制限が緩む
```
