from PIL import Image, ImageDraw

def load_logo_transparent(path, bg_rgb, tol=14):
    logo = Image.open(path).convert("RGBA")
    datas = logo.getdata()
    newdata = []
    for p in datas:
        r, g, b = p[0], p[1], p[2]
        a = p[3] if len(p) > 3 else 255
        if all(abs(c - t) < tol for c, t in zip((r, g, b), bg_rgb)):
            newdata.append((r, g, b, 0))
        else:
            newdata.append((r, g, b, a))
    logo.putdata(newdata)
    return logo

W, H = 1080, 1350
bg = Image.new("RGB", (W, H), (235, 233, 228))
draw = ImageDraw.Draw(bg)

cx = W / 2
shoulder_y = H * 0.20
hem_y = H * 0.78
shoulder_w = W * 0.30
hem_w = W * 0.46
neck_w = W * 0.10
armhole_in = W * 0.07

body = [
    (cx - neck_w, shoulder_y),
    (cx - shoulder_w, shoulder_y),
    (cx - shoulder_w + armhole_in, shoulder_y + H*0.10),
    (cx - hem_w / 2, hem_y),
    (cx + hem_w / 2, hem_y),
    (cx + shoulder_w - armhole_in, shoulder_y + H*0.10),
    (cx + shoulder_w, shoulder_y),
    (cx + neck_w, shoulder_y),
    (cx, shoulder_y + H * 0.035),
]
draw.polygon(body, fill=(250, 250, 248), outline=(210, 208, 202))

for fx, fy1, fy2 in [(-0.10, 0.30, 0.72), (0.05, 0.28, 0.75), (0.16, 0.32, 0.68)]:
    x = cx + W * fx
    draw.line([(x, H * fy1), (x + W*0.02, H * fy2)], fill=(222, 220, 214), width=3)

logo1 = load_logo_transparent(
    "/Users/takuha/scripts/reel-host/daihon/design/maruchan_logo_v2.png", (237, 229, 209)
)
logo2 = load_logo_transparent(
    "/Users/takuha/scripts/reel-host/daihon/design/maruchan_badge2_mj_raw.png", (255, 255, 255)
)

size1 = int(W * 0.20)
l1 = logo1.resize((size1, size1), Image.LANCZOS)
p1x = int(cx - shoulder_w * 0.42 - size1 / 2)
p1y = int(shoulder_y + H * 0.08)
bg.paste(l1, (p1x, p1y), l1)

size2 = int(W * 0.14)
l2 = logo2.resize((size2, size2), Image.LANCZOS)
p2x = int(p1x + size1 + W * 0.02)
p2y = int(p1y + size1 * 0.35)
bg.paste(l2, (p2x, p2y), l2)

bg.save("/Users/takuha/scripts/reel-host/daihon/design/maruchan_shirt_mockup_v2_2logos.png")
print("done")
