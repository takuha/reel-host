# reel-host

リール投稿用の一時置き場。Meta Graph API が動画を取得するための公開URLを作るだけのリポジトリ。
投稿が済んだ動画は `reel_host.sh clean` で削除される。

Graph API を叩いて実際に投稿する処理はここには置かない。ここは公開URLを出す係。

## 使い方

```sh
./reel_host.sh add aoyagi ~/Movies/reel001.mp4   # 公開して URL を出す
./reel_host.sh list aoyagi                       # ホスティング中の動画
./reel_host.sh clean aoyagi                      # 投稿が済んだら消す
```

`add` は GitHub Pages が実際に配信を始めるまで待ってから URL を出す。プッシュ直後は
まだ 404 なので、待たずに Graph API へ渡すと投稿が失敗する。

## アカウントを分ける

動画は `videos/<account>/` に置かれ、公開URLもそのままアカウント単位で分かれる。

```
videos/aoyagi/reel001.mp4
  → https://takuha.github.io/reel-host/videos/aoyagi/reel001.mp4
```

アカウントを増やすときにこのリポジトリ側でやることは無く、`add` に別の名前を渡すだけ。
ただし**投稿側は別**で、Meta のアクセストークンは認可したアカウントにしか使えない。
アカウントを増やしたら、そのアカウントを含めて認可をやり直し、そのアカウント自身の
IG ユーザー ID を取得する必要がある。

## 設定

環境変数で上書きできる。

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `REEL_HOST_BASE_URL` | `https://takuha.github.io/reel-host` | 公開URLの先頭 |
| `REEL_HOST_BRANCH` | `main` | GitHub Pages の配信元ブランチ |
| `REEL_HOST_WAIT_TRIES` | `30` | 公開されるまでの確認回数 |
| `REEL_HOST_WAIT_INTERVAL` | `5` | 確認の間隔（秒） |
