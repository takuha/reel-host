# reel-host

リールを投稿するための一式。役割が3つに分かれている。

| スクリプト | 役割 |
| --- | --- |
| `reel_host.sh` | 動画（ローカルのファイルか動画URL）を GitHub Pages に載せて公開URLを出す／投稿後に消す |
| `reel_post.sh` | その公開URLを Meta Graph API に渡してリールとして投稿する |
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

## 動画URLから投稿する

手元にファイルが無くても、動画ページのURLをそのまま渡せる。TikTok など
`yt-dlp` が対応しているサイトなら、取得から投稿まで一度で通る。

```sh
./reel_post.sh publish aoyagi "https://vt.tiktok.com/XXXXXXXX/" "本文"
./reel_host.sh add aoyagi "https://vt.tiktok.com/XXXXXXXX/"   # 公開だけ
```

`http://` か `https://` で始まる引数はURLとして扱い、それ以外はローカルの
ファイルとして扱う。動画は一時ディレクトリに落としてから公開し、終了時に消す
ので、作業ディレクトリは汚れない。

取得するのは **H.264 の MP4** を最優先。TikTok は同じ動画を HEVC(h265) でも
配信していて、そちらの方が解像度が高いため、指定しないと h265 を掴む。Meta の
リールは H.264 が対象で、h265 を渡すと変換段階で `status_code=ERROR` になる。
そのため解像度より H.264 を優先する（TikTok の場合、1080p ではなく 720p を取る
ことになる）。

`yt-dlp` が要る。

```sh
brew install yt-dlp    # または pip install -U yt-dlp
```

`publish` の第2引数はダウンロード元のURL、`post` の第2引数は**すでに公開されて
いる動画の直リンク**で、意味が違うので注意。`post` にTikTokのページURLを渡しても
Meta 側が動画を取得できない。

投稿できる権利のある動画かどうかは自分で確認すること。スクリプトは何も判断しない。

`add` は GitHub Pages が実際に配信を始めるまで待ってから URL を出す。プッシュ直後は
まだ 404 で、待たずに Graph API へ渡すと動画取得に失敗するため。

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

`REEL_GRAPH_VERSION` はバージョン切れを言われたら上げる。既定値が現時点の最新とは
限らないので、エラーが出たら Meta の changelog で確認すること。

必要なコマンドは `curl` と、`jq` または `python3` のどちらか。動画URLを渡す場合は
`yt-dlp` も要る（ローカルのファイルだけを扱うなら不要）。
