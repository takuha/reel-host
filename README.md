# reel-host

リール投稿用の一時置き場。Meta Graph API が動画を取得するための公開URLを作るだけのリポジトリ。
投稿が済んだ動画は `reel_host.sh clean` で削除される。

## scripts/

- `yt_shorts_upload.py` — ローカルの mp4 を YouTube に送る。予約投稿つき。
  セットアップは [scripts/README_youtube.md](scripts/README_youtube.md)。
