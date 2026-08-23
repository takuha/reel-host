from PIL import Image, ImageDraw

def make_shirt_mockup(logo_path, path, size=(1080, 1350)):
    W, H = size
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

    logo = Image.open(logo_path).convert("RGBA")
    # make the cream background of the logo transparent so it sits on the fabric
    datas = logo.getdata()
    newdata = []
    for r, g, b, a in [(*p[:3], p[3] if len(p) > 3 else 255) for p in datas]:
        if abs(r - 237) < 12 and abs(g - 229) < 12 and abs(b - 209) < 12:
            newdata.append((r, g, b, 0))
        else:
            newdata.append((r, g, b, a))
    logo.putdata(newdata)

    logo_size = int(W * 0.22)
    logo_small = logo.resize((logo_size, logo_size), Image.LANCZOS)
    px = int(cx - shoulder_w * 0.35 - logo_size / 2)
    py = int(shoulder_y + H * 0.09)
    bg.paste(logo_small, (px, py), logo_small)

    bg.save(path)

make_shirt_mockup(
    "/Users/takuha/scripts/reel-host/daihon/design/maruchan_logo_v2.png",
    "/Users/takuha/scripts/reel-host/daihon/design/maruchan_shirt_mockup_v2.png",
)
print("done")
