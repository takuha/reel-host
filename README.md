# reel-host

リールを投稿するための一式。役割が3つに分かれている。

| スクリプト | 役割 |
| --- | --- |
| `reel_host.sh` | 動画を GitHub Pages に載せて公開URLを出す／投稿後に消す |
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

## 使い方

```sh
./reel_post.sh accounts                                   # 設定済みアカウント
./reel_post.sh check aoyagi                               # 接続確認
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

一覧そのものが取れない場合は、トークン自体が無効か期限切れ。

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

必要なコマンドは `curl` と、`jq` または `python3` のどちらか。
