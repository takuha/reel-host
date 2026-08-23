import math
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

random.seed(7)

FONT_MARU = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"

def wobbly_circle_points(cx, cy, r, n=60, jitter=3.5):
    pts = []
    for i in range(n):
        a = (2 * math.pi) * i / n
        rr = r + random.uniform(-jitter, jitter)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts

def make_logo(path, size=800, ink=(20, 20, 20, 255)):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy, r = size / 2, size / 2, size * 0.36

    # hand-drawn feel: draw the wobbly circle outline twice with slight offset, like a marker doubling back
    for offset in [(0, 0), (4, -3)]:
        pts = wobbly_circle_points(cx + offset[0], cy + offset[1], r, n=72, jitter=6)
        draw.line(pts + [pts[0]], fill=ink, width=14, joint="curve")

    # slight overlap stroke where a marker would start/end (top-right, like closing a circle by hand)
    draw.line(wobbly_circle_points(cx, cy, r, n=10, jitter=6)[0:3], fill=ink, width=16)

    font = ImageFont.truetype(FONT_MARU, int(size * 0.30))
    text = "マル"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1] - size * 0.02), text, font=font, fill=ink)

    img.save(path)
    return img

def make_shirt_mockup(logo_img, path, size=(1080, 1350)):
    W, H = size
    bg = Image.new("RGB", (W, H), (235, 233, 228))
    draw = ImageDraw.Draw(bg)

    # simple white sleeveless top silhouette (tank-top shape)
    cx = W / 2
    shoulder_y = H * 0.20
    hem_y = H * 0.78
    shoulder_w = W * 0.30
    hem_w = W * 0.46
    neck_w = W * 0.10
    armhole_in = W * 0.07

    body = [
        (cx - neck_w, shoulder_y),                       # left neck
        (cx - shoulder_w, shoulder_y),                   # left shoulder tip
        (cx - shoulder_w + armhole_in, shoulder_y + H*0.10),  # left armpit
        (cx - hem_w / 2, hem_y),                          # left hem
        (cx + hem_w / 2, hem_y),                          # right hem
        (cx + shoulder_w - armhole_in, shoulder_y + H*0.10),  # right armpit
        (cx + shoulder_w, shoulder_y),                    # right shoulder tip
        (cx + neck_w, shoulder_y),                        # right neck
        (cx, shoulder_y + H * 0.035),                     # neckline dip
    ]
    draw.polygon(body, fill=(250, 250, 248), outline=(210, 208, 202))

    # soft shading for fabric folds
    for fx, fy1, fy2 in [(-0.10, 0.30, 0.72), (0.05, 0.28, 0.75), (0.16, 0.32, 0.68)]:
        x = cx + W * fx
        draw.line([(x, H * fy1), (x + W*0.02, H * fy2)], fill=(222, 220, 214), width=3)

    logo_size = int(W * 0.22)
    logo_small = logo_img.resize((logo_size, logo_size), Image.LANCZOS)
    px = int(cx - shoulder_w * 0.35 - logo_size / 2)
    py = int(shoulder_y + H * 0.09)
    bg.paste(logo_small, (px, py), logo_small)

    bg.save(path)

logo = make_logo("/Users/takuha/scripts/reel-host/daihon/design/maruchan_logo_v1.png")
make_shirt_mockup(logo, "/Users/takuha/scripts/reel-host/daihon/design/maruchan_shirt_mockup_v1.png")
print("done")
