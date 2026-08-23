from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT_MARU = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"

src = Image.open("/Users/takuha/Downloads/maruchan_badge_v1.png").convert("RGBA")
draw = ImageDraw.Draw(src)

W, H = src.size
cx, cy = W / 2, H / 2

font = ImageFont.truetype(FONT_MARU, int(W * 0.24))
text = "マル"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
pos = (cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1])

# soft gold-black gradient feel: draw a subtle shadow then solid ink text, matching the badge palette
shadow = Image.new("RGBA", src.size, (0, 0, 0, 0))
sdraw = ImageDraw.Draw(shadow)
sdraw.text((pos[0] + 4, pos[1] + 4), text, font=font, fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(6))
src = Image.alpha_composite(src, shadow)
draw = ImageDraw.Draw(src)
draw.text(pos, text, font=font, fill=(26, 24, 20, 255))

src.convert("RGB").save("/Users/takuha/scripts/reel-host/daihon/design/maruchan_logo_v2.png", quality=95)
print("done")
