from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICON_PATH = os.path.join(ROOT, "assets", "images", "app_icon.png")
ICON_FG_PATH = os.path.join(ROOT, "assets", "images", "app_icon_fg.png")

base = Image.open(ICON_PATH).convert("RGBA")
size = base.size[0]

# Sample colors from the existing icon to keep the same palette.
ring_samples = []
for x in range(size):
    for y in (6, 7, 8):
        r, g, b, a = base.getpixel((x, y))
        if a > 0 and r > 120 and g > 90 and b < 120:
            ring_samples.append((r, g, b))
if ring_samples:
    ring_color = tuple(int(sum(c[i] for c in ring_samples) / len(ring_samples)) for i in range(3))
else:
    ring_color = (201, 165, 71)

center_color = base.getpixel((size // 2, size // 2))[:3]
edge_color = base.getpixel((size // 2, int(size * 0.12)))[:3]

img = Image.new("RGBA", (size, size), edge_color + (255,))
px = img.load()

cx, cy = size / 2.0, size / 2.0
radius = size * 0.46
for y in range(size):
    dy = y - cy
    for x in range(size):
        dx = x - cx
        d = (dx * dx + dy * dy) ** 0.5
        if d <= radius:
            t = min(max(d / radius, 0.0), 1.0)
            r = int(center_color[0] * (1 - t) + edge_color[0] * t)
            g = int(center_color[1] * (1 - t) + edge_color[1] * t)
            b = int(center_color[2] * (1 - t) + edge_color[2] * t)
            px[x, y] = (r, g, b, 255)

# Ring
ring_width = int(size * 0.01)
ring_bbox = [
    int(cx - radius),
    int(cy - radius),
    int(cx + radius),
    int(cy + radius),
]

# Subtle star field in the background + soft halo around the text
draw = ImageDraw.Draw(img)
star_positions = [
    (int(cx - size * 0.30), int(cy - size * 0.20)),
    (int(cx + size * 0.26), int(cy - size * 0.22)),
    (int(cx + size * 0.30), int(cy + size * 0.14)),
    (int(cx - size * 0.24), int(cy + size * 0.18)),
    (int(cx - size * 0.04), int(cy - size * 0.30)),
    (int(cx + size * 0.06), int(cy + size * 0.28)),
]
star_sizes = [int(size * 0.05), int(size * 0.04), int(size * 0.045), int(size * 0.035), int(size * 0.03), int(size * 0.028)]
star_alpha = 120

for (sx, sy), s in zip(star_positions, star_sizes):
    draw.ellipse([sx, sy, sx + s, sy + s], fill=ring_color + (star_alpha,))
    draw.ellipse([sx + 1, sy + 1, sx + s - 1, sy + s - 1], fill=(0, 0, 0, 50))

# Text
text = "Lamssa"
font_paths = [
    r"C:\Windows\Fonts\timesbd.ttf",
    r"C:\Windows\Fonts\georgiab.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\times.ttf",
    r"C:\Windows\Fonts\arial.ttf",
]
font_path = next((p for p in font_paths if os.path.exists(p)), None)
font_size = int(size * 0.22)
if font_path:
    font = ImageFont.truetype(font_path, font_size)
else:
    font = ImageFont.load_default()

max_width = int(size * 0.62)

while True:
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    if text_w <= max_width or font_size <= 10:
        break
    font_size = int(font_size * 0.95)
    if font_path:
        font = ImageFont.truetype(font_path, font_size)
    else:
        font = ImageFont.load_default()
        break

# Ring after background to stay crisp.
draw.ellipse(ring_bbox, outline=ring_color + (255,), width=ring_width)

text_x = int(cx - text_w / 2)
text_y = int(cy - text_h / 2)
shadow_color = (0, 0, 0, 90)

draw.text((text_x - 1, text_y - 1), text, font=font, fill=ring_color + (40,))
draw.text((text_x + 1, text_y - 1), text, font=font, fill=ring_color + (40,))
draw.text((text_x - 1, text_y + 1), text, font=font, fill=ring_color + (40,))
draw.text((text_x + 1, text_y + 1), text, font=font, fill=ring_color + (40,))
draw.text((text_x + 2, text_y + 2), text, font=font, fill=shadow_color)
draw.text((text_x, text_y), text, font=font, fill=ring_color + (255,))

# Modern sparkle accents
spark_positions = [
    (int(cx - size * 0.18), int(cy - size * 0.16)),
    (int(cx + size * 0.18), int(cy - size * 0.14)),
    (int(cx + size * 0.22), int(cy + size * 0.10)),
]
spark_size = int(size * 0.06)
spark_line = max(1, int(size * 0.006))

for sx, sy in spark_positions:
    cxs = sx + spark_size // 2
    cys = sy + spark_size // 2
    draw.line([(cxs - spark_size // 2, cys), (cxs + spark_size // 2, cys)], fill=ring_color + (220,), width=spark_line)
    draw.line([(cxs, cys - spark_size // 2), (cxs, cys + spark_size // 2)], fill=ring_color + (220,), width=spark_line)

img.save(ICON_PATH)
img.save(ICON_FG_PATH)
