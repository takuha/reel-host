# reel-host

Instagram リールを投稿するための一式。Meta Graph API が動画を「公開URLから取得」する
方式なので、投稿前にどこかへ公開しておく必要がある。その置き場がこのリポジトリ。

詳しい使い方は README.md にある。ここには**調べ直すと手間がかかること**だけ書く。

## 構成

| ファイル | 役割 |
| --- | --- |
| `reel_host.sh` | 動画を GitHub Pages に載せて公開URLを出す／消す |
| `reel_post.sh` | その URL を Graph API に渡して投稿する。`check` `refresh` もここ |
| `cleanup.sh` | 消し忘れた動画を時間経過で回収する保険 |

アカウントは `.env` の接頭辞で決まる（`AOYAGI_` → `aoyagi`）。増やすときは2行足すだけで、
スクリプトは触らない。

## 未解決の課題

### cleanup.sh の自動実行が確認できていない

README には「毎朝9時に自動実行される」とあるが、**それを行う仕組みがリポジトリ内に無い**。
`.github/` は存在せず、Actions のワークフローは GitHub が自動生成する
`pages-build-deployment` の1つだけ。

ローカルの cron / launchd で回しているなら問題ない。確認する方法:

```sh
crontab -l | grep -i cleanup
launchctl list | grep -i cleanup
```

**何も出ない場合は保険が掛かっていない**（消し忘れた動画が公開URLに残り続ける）ので、
`.github/workflows/cleanup.yml` を追加する。ローカルで回っているなら二重に動くため
**追加してはいけない**。この確認が取れるまで、勝手にワークフローを足さないこと。

## 判断済みで、蒸し返さなくていいこと

### git 履歴の肥大化 — 現時点では対策不要

動画をコミットすると `git rm` しても `.git` に残り続ける、という構造上の弱点はある。
ただし 2026-08 時点の実測では**履歴に動画は1本も入っていない**。

| 項目 | 値 |
| --- | --- |
| `.git` | 568 KB |
| 履歴中の最大 blob | 11.2 KB（`reel_post.sh`） |

LFS も `.gitattributes` も履歴の書き換えも、今入れる理由がない。
**`du -sh .git` が 500 MB を超えたら**置き場の変更（orphan ブランチ／R2・S3 等）を検討する。

### テスト・CI は入れない

シェル3本で、実行には Meta の実トークンが要る。CI から叩けないので費用対効果が合わない。

## 環境の制約

**Claude Code on the web のセッションからは外部ネットワークに出られない。**
ネットワークポリシーが以下を拒否する（プロキシが CONNECT に 403 を返す）。

```
context7.com  developers.facebook.com  graph.facebook.com
```

したがって web セッションでは次ができない。ローカルの Claude Code では動く。

- `.mcp.json` の context7 を使ったドキュメント取得
- `./reel_post.sh check` などの実際の接続確認・投稿

**この環境で「繋がらない」と言われたら、まずトークンではなくネットワーク制限を疑う。**
確認は `curl -sS "$HTTPS_PROXY/__agentproxy/status"`。

## トークン

Graph API Explorer が出すトークンは**1時間で切れる**。`./reel_post.sh refresh <account>`
で60日に延長して使う。60日ごとに打ち直しが要る。

`code 190` は期限切れ。トークンは**認可したアカウントにしか使えない**ので、
アカウントを増やしたら認可を取り直す（既存トークンの流用は不可）。

## 本文を書くとき

`.claude/skills/reel-caption/` のスキルを使う。**動画の中身が分からないうちは書き始めない。**
ファイル名から内容を推測しないこと。
