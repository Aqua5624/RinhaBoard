import math
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersample canvas

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def diagonal_gradient(size, c1, c2, c3):
    small = 512
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            if t < 0.5:
                px[x, y] = lerp(c1, c2, t * 2)
            else:
                px[x, y] = lerp(c2, c3, (t - 0.5) * 2)
    return img.resize((size, size), Image.BICUBIC)

def sparkle_points(cx, cy, r, exponent=4.0):
    # Generalised astroid: sharp cusps at the four cardinal points, concave sides.
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, sn = math.cos(t), math.sin(t)
        x = r * math.copysign(abs(c) ** exponent, c)
        y = r * math.copysign(abs(sn) ** exponent, sn)
        pts.append((cx + x, cy + y))
    return pts

# --- background: violet -> purple -> magenta
bg = diagonal_gradient(S, (104, 52, 224), (162, 89, 230), (238, 92, 196)).convert("RGBA")

# soft glow behind keycap
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([S * 0.08, S * 0.02, S * 0.98, S * 0.92], fill=(255, 190, 240, 90))
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.06))
bg = Image.alpha_composite(bg, glow)

cx = cy = S / 2
cap_half = S * 0.315
radius = S * 0.085

# keycap shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([cx - cap_half, cy - cap_half + S * 0.018, cx + cap_half, cy + cap_half + S * 0.018],
                     radius=radius, fill=(40, 0, 90, 130))
shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.012))
bg = Image.alpha_composite(bg, shadow)

# keycap body: white with a whisper of lavender at the bottom
cap_grad = diagonal_gradient(S, (255, 255, 255), (250, 246, 255), (238, 228, 255))
cap_mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(cap_mask)
md.rounded_rectangle([cx - cap_half, cy - cap_half, cx + cap_half, cy + cap_half], radius=radius, fill=255)
bg.paste(cap_grad, (0, 0), cap_mask)

d = ImageDraw.Draw(bg)
# thin inner border for a keycap edge
d.rounded_rectangle([cx - cap_half + S * 0.006, cy - cap_half + S * 0.006, cx + cap_half - S * 0.006, cy + cap_half - S * 0.006],
                    radius=radius - S * 0.006, outline=(120, 70, 200, 60), width=int(S * 0.004))

# main sparkle filled with the brand gradient
spark_grad = diagonal_gradient(S, (122, 62, 232), (178, 92, 232), (240, 96, 188))
spark_mask = Image.new("L", (S, S), 0)
smd = ImageDraw.Draw(spark_mask)
smd.polygon(sparkle_points(cx, cy - S * 0.01, S * 0.225), fill=255)
bg.paste(spark_grad, (0, 0), spark_mask)

# small white sparkles on the background
d = ImageDraw.Draw(bg)
for (sx, sy, sr, alpha) in [(0.845, 0.155, 0.052, 235), (0.135, 0.80, 0.038, 210), (0.80, 0.86, 0.026, 190)]:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.polygon(sparkle_points(S * sx, S * sy, S * sr), fill=(255, 255, 255, alpha))
    bg = Image.alpha_composite(bg, layer)
    d = ImageDraw.Draw(bg)
# tiny dots
for (sx, sy, sr) in [(0.16, 0.18, 0.010), (0.885, 0.42, 0.008), (0.10, 0.55, 0.007)]:
    d.ellipse([S * sx - S * sr, S * sy - S * sr, S * sx + S * sr, S * sy + S * sr], fill=(255, 255, 255, 200))

icon = bg.convert("RGB").resize((1024, 1024), Image.LANCZOS)
icon.save("/home/hatch/workspace/ios-apps/rinhaboard/RinhaBoard/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
icon.save("/home/hatch/workspace/ios-apps/rinhaboard/icon-work/icon-preview.png")
print("saved", icon.size, icon.mode)
