from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT_MARU = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"

src = Image.open("/Users/takuha/scripts/reel-host/daihon/design/maruchan_badge3_mj_raw.png").convert("RGBA")
draw = ImageDraw.Draw(src)

W, H = src.size
cx, cy = W / 2, H / 2

font = ImageFont.truetype(FONT_MARU, int(W * 0.22))
text = "マル"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
pos = (cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1])

# subtle gold glow behind the text to match the ring's metallic tone
glow = Image.new("RGBA", src.size, (0, 0, 0, 0))
gdraw = ImageDraw.Draw(glow)
gdraw.text((pos[0], pos[1]), text, font=font, fill=(212, 168, 90, 140))
glow = glow.filter(ImageFilter.GaussianBlur(10))
src = Image.alpha_composite(src, glow)
draw = ImageDraw.Draw(src)
draw.text(pos, text, font=font, fill=(238, 220, 180, 255))

src.convert("RGB").save("/Users/takuha/scripts/reel-host/daihon/design/maruchan_logo_v3.png", quality=95)
print("done")
