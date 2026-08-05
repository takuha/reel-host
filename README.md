# reel-host

リール投稿用の一時置き場。Meta Graph API が動画を取得するための公開URLを作るだけのリポジトリ。
投稿が済んだ動画は `reel_host.sh clean` で削除される。

手元で消し忘れた分は `cleanup.sh` が拾う。コミットから3日以上経った動画を削除して push するだけのスクリプトで、
毎朝9時に自動実行される。対象を確認するだけなら `./cleanup.sh --dry-run`、保持期間を変えるなら `RETENTION_DAYS=7 ./cleanup.sh`。
