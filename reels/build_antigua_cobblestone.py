#!/usr/bin/env python3
"""アンティグアの石畳リールを組み立てる。

実写素材なしで完結するタイポグラフィ版。背景の石畳は手続き的に描いた丸石で、
歩いているようにゆっくり流れる。実写に差し替えるときは load_backdrop() を
差し替えれば、テロップのタイミングはそのまま使える。

  python3 reels/build_antigua_cobblestone.py -o out/antigua.mp4
"""

import argparse
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
FPS = 30
DURATION = 30.0
FONT_PATH = "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"

CREAM = (242, 235, 224)
ACCENT = (224, 143, 62)      # アンティグアの黄土色の壁
DANGER = (198, 63, 51)       # ✗ 用
INK = (18, 15, 13)

TILE_H = 2400                # 背景タイルの高さ。これ単位でループする
SCROLL = 62.0                # px/秒。歩く速度に見えるくらい

# (開始, 終了, [(文字, サイズ種別, 色), ...], 装飾)
#   サイズ種別: "s" 小 / "m" 中 / "l" 大 / "xl" 特大
#   装飾: None / "cross" 赤い✗を文字の下に敷く / "rule" 上に罫線
CUES = [
    (0.0,  2.4, [("この石畳", "l", CREAM),
                 ("地震の瓦礫を敷いたやつだと", "s", CREAM),
                 ("思ってた", "s", CREAM)], None),
    (2.6,  4.2, [("でも、違った", "xl", ACCENT)], None),
    (4.5,  7.2, [("説", "s", CREAM),
                 ("瓦礫を敷いた", "l", CREAM)], "cross"),
    (7.4, 10.2, [("順番が逆", "l", ACCENT),
                 ("石畳のほうが先にあった", "m", CREAM)], None),
    (10.4, 13.2, [("1773年", "l", CREAM),
                  ("サンタ・マルタ地震", "m", CREAM)], "rule"),
    (13.4, 16.2, [("崩れたあとは逆に", "m", CREAM),
                  ("資材は新首都へ運び出された", "m", CREAM)], None),
    (16.4, 18.5, [("本当の理由は", "m", CREAM)], None),
    (18.6, 21.5, [("泥", "xl", ACCENT)], None),
    (21.7, 24.5, [("雨季になると土の道が沼になり", "m", CREAM),
                  ("馬車が沈んで動けない", "m", CREAM)], None),
    (24.7, 27.4, [("だから川の石を敷いた", "l", ACCENT),
                  ("丸いのは、そのため", "m", CREAM)], None),
    (27.6, 30.0, [("都は崩れて", "l", CREAM),
                  ("道だけ残った", "l", ACCENT)], None),
]

SIZES = {"s": 52, "m": 70, "l": 104, "xl": 190}
FADE = 0.28


def stone_shape(cx, cy, rx, ry, rnd):
    """角の無い、少しいびつな輪郭。川で転がった石なので真円にはしない。"""
    pts = []
    n = 16
    wob = [rnd.uniform(0.86, 1.14) for _ in range(n)]
    for i in range(n):
        a = 2 * math.pi * i / n
        # 隣とならして、尖った頂点が出ないようにする
        k = (wob[i - 1] + wob[i] * 2 + wob[(i + 1) % n]) / 4
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return pts


def make_tile(seed=7):
    """丸石のタイルを1枚描く。上下がつながるように端の石を回り込ませる。"""
    rnd = random.Random(seed)
    # 目地は砂と石灰。石より明るくしないと石畳に見えない
    tile = Image.new("RGB", (W, TILE_H), (74, 66, 56))
    d = ImageDraw.Draw(tile)

    step = 82
    cols = W // step + 2
    rows = TILE_H // step + 2

    for row in range(rows):
        # 一段ごとに半個ずらす。実際の石畳もそう並んでいる
        offset = (step // 2) if row % 2 else 0
        for col in range(cols):
            cx = col * step + offset + rnd.randint(-11, 11)
            cy = row * step + rnd.randint(-11, 11)
            rx = rnd.randint(28, 41)
            ry = rnd.randint(26, 38)
            tone = rnd.randint(112, 186)
            base = (tone + rnd.randint(4, 18), tone, tone - rnd.randint(10, 22))
            # 上下にも同じ石を描いてループの継ぎ目を消す
            for dy in (-TILE_H, 0, TILE_H):
                y = cy + dy
                if y < -70 or y > TILE_H + 70:
                    continue
                pts = stone_shape(cx, y, rx, ry, random.Random(cx * 31 + cy))
                shade = tuple(max(0, c - 46) for c in base)
                # 右下に影を落として、石を浮かせる
                d.polygon([(px + 4, py + 5) for px, py in pts], fill=shade)
                d.polygon(pts, fill=base)
                # 左上のハイライトで丸みを出す
                hi = tuple(min(255, c + 40) for c in base)
                d.ellipse([cx - rx * 0.58, y - ry * 0.62,
                           cx + rx * 0.04, y - ry * 0.06], fill=hi)

    tile = tile.filter(ImageFilter.GaussianBlur(1.0))
    return tile


def vignette():
    """中央を明るく、周辺を落とすマスク。テロップを読ませるため。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx = (xx - W / 2) / (W / 2)
    ny = (yy - H / 2) / (H / 2)
    r = np.sqrt(nx ** 2 + (ny * 0.72) ** 2)          # 縦長なので縦を弱める
    m = np.clip((r - 0.16) / 0.95, 0, 1) ** 1.4
    # 中央にも薄くかけて、明るい石の上でも文字が浮くようにする
    m = 0.10 + 0.62 * m
    return Image.fromarray((m * 255).astype(np.uint8), "L").filter(
        ImageFilter.GaussianBlur(24))


def font(px):
    return ImageFont.truetype(FONT_PATH, px)


def draw_block(canvas, block, alpha, rise, decor):
    """行をまとめて中央に置く。alpha はフェード、rise は立ち上がりの持ち上げ。

    block は (文字, サイズ種別, 色) の並び。行ごとに大きさを変えられるので、
    「小さい前振り＋大きい本題」を1ブロックとして組める。
    """
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    metrics = []
    for text, kind, color in block:
        px = SIZES[kind]
        f = font(px)
        sw = max(1, px // 24)
        box = d.textbbox((0, 0), text, font=f, stroke_width=sw)
        metrics.append((text, f, color, sw, box[2] - box[0], box[3] - box[1], px))

    gaps = [int(max(m[6] for m in metrics) * 0.34)] * max(0, len(metrics) - 1)
    total = sum(m[5] for m in metrics) + sum(gaps)
    top = (H - total) // 2 + rise
    widest = max(m[4] for m in metrics)

    # 文字の下に暗い座布団を敷く。明るい石の上でも白が沈まないように
    plate = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle(
        [(W - widest) // 2 - 70, top - 70, (W + widest) // 2 + 70, top + total + 70],
        radius=80, fill=INK + (150,))
    layer.alpha_composite(plate.filter(ImageFilter.GaussianBlur(38)))

    if decor == "cross":
        # ✗ はフォントに無いことがあるので線で描く。文字の下に敷いて可読性を守る
        cx, cy = W // 2, top + total // 2
        rw, rh = int(widest * 0.62), int(total * 0.78)
        for s in (-1, 1):
            d.line([cx - rw, cy - rh * s, cx + rw, cy + rh * s],
                   fill=DANGER + (205,), width=18)

    if decor == "rule":
        rw = int(widest * 0.42)
        d.line([(W - rw) // 2, top - 46, (W + rw) // 2, top - 46],
               fill=ACCENT + (255,), width=7)

    y = top
    for text, f, color, sw, w, h, px in metrics:
        d.text(((W - w) // 2, y), text, font=f, fill=color + (255,),
               stroke_width=sw, stroke_fill=INK + (215,))
        y += h + (gaps.pop(0) if gaps else 0)

    if alpha < 255:
        a = layer.getchannel("A").point(lambda v: v * alpha // 255)
        layer.putalpha(a)
    canvas.alpha_composite(layer)


def ease(x):
    return 1 - (1 - x) ** 3


def build(out_path, ffmpeg):
    tile = make_tile()
    vig = vignette()
    shade = Image.new("RGB", (W, H), (0, 0, 0))

    tmp = tempfile.mkdtemp(prefix="antigua-frames-")
    total = int(DURATION * FPS)
    try:
        for i in range(total):
            t = i / FPS
            # 背景をスクロール。歩いている感じを出す
            off = int((t * SCROLL) % TILE_H)
            bg = Image.new("RGB", (W, H))
            bg.paste(tile, (0, -off))
            bg.paste(tile, (0, -off + TILE_H))
            # ゆっくり寄る
            z = 1.0 + 0.05 * (t / DURATION)
            zw, zh = int(W * z), int(H * z)
            bg = bg.resize((zw, zh), Image.BILINEAR).crop(
                ((zw - W) // 2, (zh - H) // 2, (zw - W) // 2 + W, (zh - H) // 2 + H))

            bg = Image.composite(shade, bg, vig)
            frame = bg.convert("RGBA")

            for start, end, block, decor in CUES:
                if not (start <= t < end):
                    continue
                if t - start < FADE:
                    p = (t - start) / FADE
                    alpha, rise = int(255 * ease(p)), int(34 * (1 - ease(p)))
                elif end - t < FADE:
                    p = (end - t) / FADE
                    alpha, rise = int(255 * ease(p)), 0
                else:
                    alpha, rise = 255, 0
                draw_block(frame, block, alpha, rise, decor)

            frame.convert("RGB").save(os.path.join(tmp, f"{i:05d}.jpg"), quality=95)
            if i % 60 == 0:
                print(f"  {i}/{total} フレーム", file=sys.stderr)

        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        cmd = [
            ffmpeg, "-y",
            "-framerate", str(FPS), "-i", os.path.join(tmp, "%05d.jpg"),
            # Instagram は音声トラックの無い動画で失敗することがあるので無音を足す
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
            "-shortest",
            "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
            "-pix_fmt", "yuv420p", "-crf", "20", "-preset", "medium",
            "-r", str(FPS), "-g", str(FPS * 2),
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100",
            "-movflags", "+faststart",
            out_path,
        ]
        subprocess.run(cmd, check=True, capture_output=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return out_path


def find_ffmpeg():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        sys.exit("ffmpeg が見つからない。pip install imageio-ffmpeg で入る。")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="out/antigua-cobblestone.mp4")
    a = ap.parse_args()
    print("書き出し:", build(a.out, find_ffmpeg()))
