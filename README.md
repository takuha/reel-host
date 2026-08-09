# reel-host

リールを投稿するための一式。役割が分かれている。

| スクリプト | 役割 |
| --- | --- |
| `reel_fetch.sh` | TikTok などの共有URLから動画の元ファイルを取ってくる |
| `reel_host.sh` | 動画を GitHub Pages に載せて公開URLを出す／投稿後に消す |
| `reel_post.sh` | その公開URLを Meta Graph API に渡してリールとして投稿する |
| `reel_series.sh` | 連載シリーズの台本を持ち、本文を組み立てて投稿まで運ぶ |
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
   pages_show_list  pages_read_engagement  business_management
   ```

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

## 連載を回す

同じ型のリールを続けて出すなら `reel_series.sh` を使う。**1話 = 1ファイル**で、
台本と投稿本文を `series/<シリーズ>/episodes/NNN-<slug>.md` に置いておく。

```sh
./reel_series.sh list                       # 全話の状態
./reel_series.sh next                       # 次に投稿する回
./reel_series.sh new hanaya 町の花屋        # 次の番号で台本を作る
./reel_series.sh show 1                     # 台本を読む
./reel_series.sh caption 1                  # 投稿本文を組み立てて確認する
./reel_series.sh post 1 ~/Movies/reel001.mp4
```

`post` は本文を組み立てて `reel_post.sh publish` に渡すだけ。投稿の中身
（ホスティング → 投稿 → 後片付け）はこれまでと同じ。動画はファイルでも共有URLでもよく、
台本の `video` 欄を埋めておけば引数は省略できる。

投稿が通ると台本の `status` `media_id` `posted_at` が書き換わる。**同じ回を二度投稿する
ことはできない**（撮り直して出し直すなら `status` を `ready` に戻す）。投稿に失敗した
ときは台本に触らないので、直してもう一度打てばいい。

`--dry-run` を付けると、投稿せずに本文と投稿先だけ出す。

```sh
./reel_series.sh post 1 --dry-run
```

投稿本文は3つをつないで作る。話数の見出しとCTAとハッシュタグを毎回手で書かなくてよい。

| 部分 | どこから |
| --- | --- |
| `第N話｜題材` | ファイル名の番号と台本の `title` |
| 本文 | 台本の `## キャプション` |
| CTA | `series.md` の `## CTA` |
| ハッシュタグ | `series.md` の `hashtags` ＋ 台本の `hashtags` |

`<話>` は番号でもスラッグの一部でもファイルパスでもいい。`1` も `001` も `hanaya` も
同じ回を指す。当てはまる回が複数あるときは、候補を出して止まる。

投稿先は台本の `account` を見て、空なら `series.md` の `account` を使う。シリーズごと
別アカウントで出すなら `series.md` 側だけ変えればいい。

### シリーズを増やす

既定は `series/ai-business`（「もしもこれをAI駆使してちゃんとビジネスしたら？」）。
別のシリーズは `REEL_SERIES` で切り替える。

```sh
REEL_SERIES=other ./reel_series.sh list
```

新しいシリーズは `series/<名前>/` に `series.md` と `template.md` を置けば動く。
既存のものをコピーして中身を書き換えるのが早い。

なお `post` は中で `reel_host.sh add` を通るので、**`main` ブランチで実行すること**。
台本を書くだけなら、どのブランチでもいい。

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
| `REEL_ENV_FILE` | `./.env` | 設定ファイルの場所 |
| `REEL_SERIES` | `ai-business` | `reel_series.sh` が見る `series/` 配下のシリーズ名 |
| `REEL_FETCH_COOKIES` | なし | URL取得に使う Cookie ファイル（Netscape 形式） |
| `REEL_FETCH_COOKIES_FROM_BROWSER` | なし | Cookie をブラウザから直接読む（`chrome` など） |

`REEL_GRAPH_VERSION` はバージョン切れを言われたら上げる。既定値が現時点の最新とは
限らないので、エラーが出たら Meta の changelog で確認すること。

必要なコマンドは `curl` と、`jq` または `python3` のどちらか。URL から投稿するなら
これに `yt-dlp` が加わる。
