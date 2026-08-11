#!/usr/bin/env python3
"""scripts.md の「投稿本文」から caption_r*.txt を起こす。

台本を直したらキャプションも作り直す。手で写すと必ずズレるので、
本文は scripts.md 側だけを正とし、ここは機械的に落とすだけにしてある。

    python3 docs/consulting/claude-code-reels/captions/build_captions.py
"""

import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCRIPTS = HERE.parent / "scripts.md"

# 「## R1｜見出し」
TITLE_RE = re.compile(r"^## (R\d)｜(.+)$", re.M)
# 「**投稿本文**」→ フェンスの中身 → 直後のハッシュタグ行
BLOCK_RE = re.compile(r"\*\*投稿本文\*\*\n```\n(.*?)```\n`(#[^`]+)`", re.S)


def main() -> int:
    src = SCRIPTS.read_text(encoding="utf-8")
    titles = TITLE_RE.findall(src)
    blocks = BLOCK_RE.findall(src)

    if not titles or len(titles) != len(blocks):
        print(
            f"台本 {len(titles)} 本に対して投稿本文 {len(blocks)} 件。"
            "数が合わないので中断する。scripts.md の書式を確認すること。",
            file=sys.stderr,
        )
        return 1

    for (rid, name), (body, tags) in zip(titles, blocks):
        text = body.rstrip("\n") + "\n\n" + tags.strip() + "\n"
        out = HERE / f"caption_{rid.lower()}.txt"
        out.write_text(text, encoding="utf-8")
        print(f"{out.name}  {len(text)}文字  {rid}｜{name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
