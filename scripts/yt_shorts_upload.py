#!/usr/bin/env python3
"""ローカルの mp4 を YouTube に上げる。予約投稿（publishAt）まで対応。

使い方は scripts/README_youtube.md を見てください。

    python3 yt_shorts_upload.py video.mp4 --title "タイトル" --publish-at "2026-08-15 21:30"

キャプションは動画と同じ名前の .txt を隣に置いておけば勝手に読みます。
"""

from __future__ import annotations

import argparse
import csv
import os
import random
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

try:
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
    from googleapiclient.http import MediaFileUpload
except ImportError:
    sys.exit(
        "ライブラリが入っていません。先にこれを1回だけ実行してください:\n"
        "  pip3 install --upgrade google-api-python-client google-auth-oauthlib"
    )

SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]
DEFAULT_TZ = "Asia/Tokyo"
DEFAULT_CATEGORY = "22"  # People & Blogs
UPLOAD_QUOTA_COST = 1600  # videos.insert 1回あたり。既定の1日枠は10,000
RETRIABLE_STATUS = {500, 502, 503, 504}
MAX_RETRIES = 5


# ---------------------------------------------------------------- 認証

def authenticate(client_secret: Path, token: Path):
    """初回だけブラウザが開きます。2回目以降は token.json を使い回します。"""
    creds = None
    if token.exists():
        creds = Credentials.from_authorized_user_file(str(token), SCOPES)

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except Exception as exc:  # 失効していたら取り直す
            print(f"  トークンを更新できませんでした（{exc}）。取り直します。")
            creds = None

    if not creds or not creds.valid:
        if not client_secret.exists():
            sys.exit(
                f"{client_secret} が見つかりません。\n"
                "Google Cloud Console で OAuth クライアント（デスクトップ アプリ）を作って、\n"
                "ダウンロードした JSON をこのパスに置いてください。手順は README_youtube.md に。"
            )
        flow = InstalledAppFlow.from_client_secrets_file(str(client_secret), SCOPES)
        creds = flow.run_local_server(port=0)
        token.write_text(creds.to_json(), encoding="utf-8")
        token.chmod(0o600)
        print(f"  認証しました。{token} に保存（このファイルは他人に渡さないでください）")

    return build("youtube", "v3", credentials=creds, cache_discovery=False)


# ---------------------------------------------------------------- 入力の整形

# 年ありの書き方
DATED_FORMATS = (
    "%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S",
    "%Y/%m/%d %H:%M", "%Y/%m/%d %H:%M:%S",
    "%Y年%m月%d日 %H:%M",
)
# 年なしの書き方（シートに「8/4」とだけ書いてある場合）
YEARLESS_FORMATS = ("%m/%d %H:%M", "%m-%d %H:%M", "%m月%d日 %H:%M")


def to_rfc3339(value: str, tz_name: str) -> str:
    """'2026-08-15 21:30' や '8/15 21:30' を、UTC の RFC3339 に直す。"""
    value = " ".join(value.split())  # 全角スペースや連続スペースをならす
    tz = ZoneInfo(tz_name)
    now = datetime.now(tz)
    parsed = None
    yearless = False

    for fmt in DATED_FORMATS:
        try:
            parsed = datetime.strptime(value, fmt)
            break
        except ValueError:
            continue

    if parsed is None:
        for fmt in YEARLESS_FORMATS:
            try:
                parsed = datetime.strptime(value, fmt).replace(year=now.year)
                yearless = True
                break
            except ValueError:
                continue

    if parsed is None:
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            sys.exit(
                f"予約日時を読めませんでした: {value!r}\n"
                "'2026-08-15 21:30' か '8/15 21:30' の形で書いてください。"
            )

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=tz)

    # 年が書いていなくて、その日付が過ぎているなら来年ぶんとみなす
    if yearless and parsed <= now:
        parsed = parsed.replace(year=now.year + 1)

    if parsed <= datetime.now(timezone.utc):
        sys.exit(f"予約日時が過去です: {value}（{tz_name} で解釈しました）")

    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_sidecar(video: Path) -> str:
    """動画と同じ名前の .txt があればキャプションとして読む。"""
    sidecar = video.with_suffix(".txt")
    if sidecar.exists():
        return sidecar.read_text(encoding="utf-8").strip()
    return ""


def build_title(raw: str, description: str, fallback: str) -> str:
    title = (raw or "").strip()
    if not title and description:
        title = description.splitlines()[0].strip()
    if not title:
        title = fallback
    # YouTube の上限は100文字。切るときは切ったと分かる形にする
    if len(title) > 100:
        title = title[:99] + "…"
    return title


# ---------------------------------------------------------------- アップロード

def upload(youtube, video: Path, *, title: str, description: str, tags: list[str],
           publish_at: str | None, privacy: str, category: str,
           made_for_kids: bool, dry_run: bool) -> str | None:
    status: dict = {
        "privacyStatus": "private" if publish_at else privacy,
        "selfDeclaredMadeForKids": made_for_kids,
    }
    if publish_at:
        # publishAt は privacyStatus=private のときだけ効く
        status["publishAt"] = publish_at

    body = {
        "snippet": {
            "title": title,
            "description": description,
            "tags": tags,
            "categoryId": category,
        },
        "status": status,
    }

    when = f"予約 {publish_at}" if publish_at else f"即時 / {privacy}"
    print(f"  {video.name}")
    print(f"    タイトル: {title}")
    print(f"    公開     : {when}")

    if dry_run:
        print("    → dry-run なので送っていません")
        return None

    media = MediaFileUpload(str(video), chunksize=4 * 1024 * 1024, resumable=True)
    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)

    response = None
    attempt = 0
    while response is None:
        try:
            progress, response = request.next_chunk()
            if progress:
                print(f"\r    送信中 {int(progress.progress() * 100)}%", end="", flush=True)
        except HttpError as exc:
            if exc.resp.status in RETRIABLE_STATUS and attempt < MAX_RETRIES:
                attempt += 1
                wait = (2 ** attempt) + random.random()
                print(f"\n    一時エラー {exc.resp.status}。{wait:.0f}秒待って再試行 ({attempt}/{MAX_RETRIES})")
                time.sleep(wait)
                continue
            if exc.resp.status == 403 and b"quota" in exc.content.lower():
                sys.exit(
                    "\n1日のAPI枠を使い切りました。\n"
                    f"アップロード1本 = {UPLOAD_QUOTA_COST} 単位、既定の枠は1日10,000単位なので"
                    "1日6本までです。日付が変わる（太平洋時間の0時）と戻ります。"
                )
            raise

    print()
    video_id = response["id"]
    print(f"    → https://youtu.be/{video_id}")
    return video_id


def set_thumbnail(youtube, video_id: str, thumb: Path) -> None:
    if not thumb.exists():
        print(f"    サムネが見つかりません: {thumb}")
        return
    try:
        youtube.thumbnails().set(videoId=video_id, media_body=MediaFileUpload(str(thumb))).execute()
        print(f"    サムネ設定: {thumb.name}")
    except HttpError as exc:
        print(f"    サムネを設定できませんでした（{exc.resp.status}）。ショートでは反映されない場合があります。")


# ---------------------------------------------------------------- CSV

CSV_COLUMNS = ("file", "title", "description", "publish_at", "tags", "thumbnail")

# 見出しは日本語でも英語でも拾う。既存のシートをそのまま渡せるように。
COLUMN_ALIASES: dict[str, tuple[str, ...]] = {
    "file": ("file", "video", "videopath", "path", "mp4", "movie",
             "動画", "動画パス", "動画ファイル", "ファイル", "ファイルパス", "パス", "素材"),
    "title": ("title", "タイトル", "題名", "見出し"),
    "description": ("description", "desc", "caption", "body",
                    "キャプション", "本文", "説明", "概要", "概要欄", "説明文"),
    "publish_at": ("publishat", "publish", "publishtime", "schedule", "scheduledat",
                   "予約", "予約日時", "投稿日時", "公開日時", "日時", "配信日時"),
    "date": ("date", "日付", "投稿日", "予約日", "公開日"),
    "time": ("time", "時刻", "時間", "投稿時刻", "予約時刻", "投稿時間"),
    "tags": ("tags", "tag", "タグ", "ハッシュタグ"),
    "thumbnail": ("thumbnail", "thumb", "サムネ", "サムネイル", "サムネパス", "サムネイルパス"),
}


def normalize_header(name: str) -> str:
    """見出しのゆれを吸収する。全角スペース・記号・大文字小文字を無視。"""
    out = (name or "").strip().lower()
    for junk in (" ", "　", "_", "-", "・", "/", "＿", "（", "）", "(", ")"):
        out = out.replace(junk, "")
    return out


def detect_columns(headers: list[str], overrides: dict[str, str]) -> dict[str, str]:
    """見出しを見て、どの列が何かを決める。--map があればそちらを優先。"""
    normalized = {normalize_header(h): h for h in headers}
    mapping: dict[str, str] = {}

    for canonical, aliases in COLUMN_ALIASES.items():
        if canonical in overrides:
            continue
        for alias in aliases:
            hit = normalized.get(normalize_header(alias))
            if hit is not None:
                mapping[canonical] = hit
                break

    for canonical, header in overrides.items():
        if canonical not in COLUMN_ALIASES:
            sys.exit(f"--map の左辺が不明です: {canonical}\n使えるのは: {', '.join(COLUMN_ALIASES)}")
        actual = normalized.get(normalize_header(header))
        if actual is None:
            sys.exit(f"--map で指定した列が CSV にありません: {header}\n見出し: {', '.join(headers)}")
        mapping[canonical] = actual

    return mapping


def parse_map_option(raw: str) -> dict[str, str]:
    overrides: dict[str, str] = {}
    for chunk in (raw or "").split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "=" not in chunk:
            sys.exit(f"--map の書き方が違います: {chunk!r}\n例: --map file=動画パス,publish_at=投稿日時")
        key, value = chunk.split("=", 1)
        overrides[key.strip()] = value.strip()
    return overrides


def load_csv(path: Path, overrides: dict[str, str], where: str) -> tuple[list[dict], dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            sys.exit(f"{path} に見出し行がありません。")
        headers = [h for h in reader.fieldnames if h]
        rows = list(reader)

    mapping = detect_columns(headers, overrides)

    if "file" not in mapping:
        sys.exit(
            f"{path} で動画のパスが入った列を見つけられませんでした。\n"
            f"見出し: {', '.join(headers)}\n"
            "この列だと分かっていれば、こう指定してください:\n"
            "  --map file=<列名>"
        )

    if where:
        if "=" not in where:
            sys.exit("--where の書き方が違います。例: --where アカウント=takuha_nanbei")
        col, needle = (part.strip() for part in where.split("=", 1))
        actual = {normalize_header(h): h for h in headers}.get(normalize_header(col))
        if actual is None:
            sys.exit(f"--where で指定した列が CSV にありません: {col}\n見出し: {', '.join(headers)}")
        before = len(rows)
        rows = [r for r in rows if needle.lower() in (r.get(actual) or "").lower()]
        print(f"  絞り込み: {actual} に「{needle}」を含む行 → {len(rows)}/{before} 行")

    file_col = mapping["file"]
    rows = [r for r in rows if (r.get(file_col) or "").strip()]
    return rows, mapping


def row_value(row: dict, mapping: dict[str, str], key: str) -> str:
    header = mapping.get(key)
    if not header:
        return ""
    return (row.get(header) or "").strip()


# ---------------------------------------------------------------- 本体

def main() -> None:
    parser = argparse.ArgumentParser(
        description="ローカルの mp4 を YouTube に上げる（予約投稿つき）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("video", nargs="?", type=Path, help="上げる mp4")
    parser.add_argument("--csv", type=Path, help="まとめて上げる。見出しは日本語でも自動で見分ける")
    parser.add_argument("--map", default="", metavar="列の対応",
                        help="見出しを手で指定する。例: --map file=動画パス,publish_at=投稿日時")
    parser.add_argument("--where", default="", metavar="列=値",
                        help="行を絞り込む。例: --where アカウント=takuha_nanbei")
    parser.add_argument("--title", default="", help="省略するとキャプション1行目を使う")
    parser.add_argument("--description", default="", help="省略すると隣の .txt を読む")
    parser.add_argument("--tags", default="", help="カンマ区切り")
    parser.add_argument("--publish-at", default="", help="'2026-08-15 21:30' 形式。指定すると予約投稿")
    parser.add_argument("--tz", default=DEFAULT_TZ, help=f"予約日時のタイムゾーン（既定 {DEFAULT_TZ}）")
    parser.add_argument("--privacy", default="public", choices=("public", "private", "unlisted"),
                        help="予約しないときの公開設定")
    parser.add_argument("--category", default=DEFAULT_CATEGORY, help="カテゴリID（既定 22 = People & Blogs）")
    parser.add_argument("--thumbnail", type=Path, help="サムネ画像")
    parser.add_argument("--made-for-kids", action="store_true", help="子ども向けとして申告する")
    parser.add_argument("--client-secret", type=Path,
                        default=Path.home() / ".config/youtube/client_secret.json")
    parser.add_argument("--token", type=Path, default=Path.home() / ".config/youtube/token.json")
    parser.add_argument("--dry-run", action="store_true", help="送らずに、何を送るかだけ出す")
    args = parser.parse_args()

    if not args.video and not args.csv:
        parser.error("mp4 か --csv のどちらかを指定してください")

    jobs: list[dict] = []
    if args.csv:
        base = args.csv.parent
        rows, mapping = load_csv(args.csv, parse_map_option(args.map), args.where)

        print("  列の対応:")
        for canonical in ("file", "title", "description", "publish_at", "date", "time", "tags", "thumbnail"):
            found = mapping.get(canonical)
            print(f"    {canonical:<12} {found if found else '—'}")
        print()

        for row in rows:
            path = Path(row_value(row, mapping, "file")).expanduser()
            if not path.is_absolute():
                path = (base / path).resolve()

            # 予約日時の列が無ければ、日付＋時刻から組み立てる
            publish_at = row_value(row, mapping, "publish_at")
            if not publish_at:
                day = row_value(row, mapping, "date")
                clock = row_value(row, mapping, "time")
                if day and clock:
                    publish_at = f"{day} {clock}"
                elif day:
                    publish_at = day

            jobs.append({
                "video": path,
                "title": row_value(row, mapping, "title"),
                "description": row_value(row, mapping, "description"),
                "tags": row_value(row, mapping, "tags"),
                "publish_at": publish_at,
                "thumbnail": row_value(row, mapping, "thumbnail"),
            })
    else:
        jobs.append({
            "video": args.video.expanduser(),
            "title": args.title,
            "description": args.description,
            "tags": args.tags,
            "publish_at": args.publish_at,
            "thumbnail": str(args.thumbnail) if args.thumbnail else "",
        })

    # 送る前に全部そろっているか見る。1本目を上げてから落ちるのが一番困る
    missing = [str(job["video"]) for job in jobs if not job["video"].exists()]
    if missing:
        sys.exit("見つからない動画があります:\n  " + "\n  ".join(missing))

    if len(jobs) * UPLOAD_QUOTA_COST > 10000:
        print(f"注意: {len(jobs)}本は1日のAPI枠（10,000単位 = 6本）を超えます。")
        print("      6本ずつに分けるか、枠の引き上げを申請してください。\n")

    if args.dry_run:
        # 何を送るか見るだけなので、認証は要らない
        youtube = None
    else:
        args.token.parent.mkdir(parents=True, exist_ok=True)
        youtube = authenticate(args.client_secret, args.token)

    print(f"\n{len(jobs)}本を処理します。\n")
    uploaded = 0
    for index, job in enumerate(jobs, start=1):
        video: Path = job["video"]
        description = job["description"] or read_sidecar(video)
        title = build_title(job["title"], description, video.stem)
        tags = [t.strip() for t in job["tags"].split(",") if t.strip()]
        publish_at = to_rfc3339(job["publish_at"], args.tz) if job["publish_at"] else None

        print(f"[{index}/{len(jobs)}]")
        try:
            video_id = upload(
                youtube, video,
                title=title, description=description, tags=tags,
                publish_at=publish_at, privacy=args.privacy, category=args.category,
                made_for_kids=args.made_for_kids, dry_run=args.dry_run,
            )
        except HttpError as exc:
            print(f"    失敗: {exc}")
            continue

        if video_id:
            uploaded += 1
            if job["thumbnail"]:
                set_thumbnail(youtube, video_id, Path(job["thumbnail"]).expanduser())
        print()

    if args.dry_run:
        print("dry-run 終わり。実際には1本も送っていません。")
    else:
        print(f"{uploaded}/{len(jobs)} 本 完了。")


if __name__ == "__main__":
    main()
