"""
启动图标：白色细圆环里一团炸开的光，深色底。
意象取自大爆炸——中心最亮，向外炸出放射状的芒，边缘化进暗里。
"""
import math

from PIL import Image, ImageDraw, ImageFilter

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
BASE = "app/src/main/res"
VIEW = 108.0
SUPER = 4
BIG = 432


def lerp(a, b, t):
    return int(round(a + (b - a) * t))


def vgrad(w, h, top, bottom):
    img = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        img.putpixel((0, y), (lerp(top[0], bottom[0], t),
                              lerp(top[1], bottom[1], t),
                              lerp(top[2], bottom[2], t)))
    return img.resize((w, h))


def rr_mask(size, box, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def render(size):
    S = int(size * SUPER)
    u = S / VIEW
    cx = cy = S / 2.0
    ring_r = 37.5 * u

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # 深色底，上略亮下略暗，避免死黑
    bg = vgrad(S, S, (0x1B, 0x20, 0x2B), (0x0C, 0x0F, 0x15)).convert("RGBA")
    canvas.paste(bg, (0, 0), rr_mask(S, [0, 0, S - 1, S - 1], int(S * 0.225)))

    # 环内垫一层更深的靛色，让光有地方落
    inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(inner).ellipse(
        [cx - ring_r + 1.5 * u, cy - ring_r + 1.5 * u, cx + ring_r - 1.5 * u, cy + ring_r - 1.5 * u],
        fill=(18, 38, 74, 255)
    )
    canvas.alpha_composite(inner)

    # 光球：从中心的白一路过渡到青蓝，再化进透明
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    core_r = 34 * u
    steps = 72
    for i in range(steps, 0, -1):
        t = i / steps
        rad = core_r * t
        if t < 0.44:
            k = t / 0.44
            col = (255, 255, 255, int(255 * (1 - k * 0.55)))
        elif t < 0.72:
            k = (t - 0.44) / 0.28
            col = (lerp(255, 176, k), lerp(255, 226, k), 255, int(lerp(140, 90, k)))
        else:
            k = (t - 0.72) / 0.28
            col = (lerp(176, 92, k), lerp(226, 156, k), lerp(255, 232, k), int(90 * (1 - k)))
        gd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=col)
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(1.6 * u)))

    # 放射芒：长短交替，短的那些更淡，看起来像光线而不是辐条
    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    for i in range(14):
        ang = math.radians(i * (360 / 14) + 8)
        long_ray = i % 2 == 0
        length = (37 * u) if long_ray else (26 * u)
        half = (0.14 if long_ray else 0.10)
        alpha = 185 if long_ray else 120

        tip = (cx + math.cos(ang) * length, cy + math.sin(ang) * length)
        p1 = (cx + math.cos(ang + half) * 2.6 * u, cy + math.sin(ang + half) * 2.6 * u)
        p2 = (cx + math.cos(ang - half) * 2.6 * u, cy + math.sin(ang - half) * 2.6 * u)
        rd.polygon([p1, tip, p2], fill=(255, 255, 255, alpha))
    canvas.alpha_composite(rays.filter(ImageFilter.GaussianBlur(0.7 * u)))

    # 白环最后画，压住溢出的光，边线才干净
    d = ImageDraw.Draw(canvas)
    d.ellipse(
        [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
        outline=(255, 255, 255, 240),
        width=max(1, int(2.6 * u))
    )

    return canvas.resize((size, size), Image.LANCZOS)


for name, size in DENSITIES.items():
    render(size).save(f"{BASE}/mipmap-{name}/ic_launcher.png")
    print(f"{name} {size}")

render(BIG).save(f"{BASE}/drawable/ic_launcher_foreground.png")
render(BIG).save("../docs/icon_v4.png")
print("done")
