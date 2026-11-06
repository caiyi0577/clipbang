"""
启动图标：白色圆角方块上浮着一枚深灰爆炸符号。
符号本身有上亮下暗的渐变、投影和中心高光，做成轻拟物而不是纯平剪影。
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


def build_burst(S, u, cx, cy):
    """画爆炸符号，返回抠好的 alpha 遮罩"""
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)

    # 尖角：角度和长度都刻意不均匀，规整的等分会变成太阳
    spikes = [
        (8, 17.5, 4.6), (37, 9.5, 6.2), (61, 14.0, 4.2), (94, 8.0, 6.0),
        (122, 16.5, 4.4), (151, 9.0, 6.4), (178, 18.0, 4.0), (207, 8.5, 5.8),
        (236, 13.5, 4.5), (263, 7.5, 6.0), (292, 16.0, 4.2), (327, 9.5, 5.6),
    ]
    for (deg, length, base) in spikes:
        ang = math.radians(deg)
        half = base / max(length, 1.0)
        tip = (cx + math.cos(ang) * length * u, cy + math.sin(ang) * length * u)
        p1 = (cx + math.cos(ang + half) * 5.4 * u, cy + math.sin(ang + half) * 5.4 * u)
        p2 = (cx + math.cos(ang - half) * 5.4 * u, cy + math.sin(ang - half) * 5.4 * u)
        d.polygon([p1, tip, p2], fill=255)

    # 中心圆压住根部
    r = 6.6 * u
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

    # 四角飞散的小点
    for (dx, dy) in [(-25, -25), (25, -24), (-24, 26), (26, 25)]:
        pr = 2.6 * u
        ox, oy = cx + dx * u, cy + dy * u
        d.ellipse([ox - pr, oy - pr, ox + pr, oy + pr], fill=255)

    return mask


def render(size):
    S = int(size * SUPER)
    u = S / VIEW
    cx = cy = S / 2.0

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shell = [0, 0, S - 1, S - 1]

    # ---------- 白色方块 ----------
    ground = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ground).rounded_rectangle(
        [u * 3, u * 6, S - u * 3, S - u * 1], radius=int(S * 0.235), fill=(74, 74, 80, 95)
    )
    canvas.alpha_composite(ground.filter(ImageFilter.GaussianBlur(u * 3.0)))

    face = vgrad(S, S, (255, 255, 255), (0xF0, 0xF0, 0xF2)).convert("RGBA")
    canvas.paste(face, (0, 0), rr_mask(S, shell, int(S * 0.235)))

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(shell, radius=int(S * 0.235),
                        outline=(212, 212, 216, 255), width=max(1, int(u * 0.55)))
    d.arc([u * 6, u * 5, S - u * 6, S - u * 5], start=196, end=344,
          fill=(255, 255, 255, 230), width=max(1, int(u * 0.8)))

    # ---------- 符号投影 ----------
    sym = build_burst(S, u, cx, cy)
    shadow_lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_lay.paste(Image.new("RGBA", (S, S), (40, 40, 46, 110)), (0, 0), sym)
    canvas.alpha_composite(shadow_lay.filter(ImageFilter.GaussianBlur(u * 1.6)).transform(
        (S, S), Image.AFFINE, (1, 0, 0, 0, 1, -u * 1.6)))

    # ---------- 符号本体：上亮下暗 ----------
    grad = vgrad(S, S, (0x5E, 0x5E, 0x64), (0x33, 0x33, 0x38)).convert("RGBA")
    canvas.paste(grad, (0, 0), sym)

    # 中心圆的高光，让它像颗球
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.ellipse([cx - 4.8 * u, cy - 5.6 * u, cx + 1.2 * u, cy - 0.2 * u],
               fill=(255, 255, 255, 42))
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (S, S), 0), sym))
    canvas.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(u * 0.9)))

    # 尖端压一道更深的边，符号才有厚度
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    ed.ellipse([cx - 6.6 * u, cy - 6.6 * u, cx + 6.6 * u, cy + 6.6 * u],
               outline=(28, 28, 32, 120), width=max(1, int(u * 0.6)))
    edge.putalpha(Image.composite(edge.getchannel("A"), Image.new("L", (S, S), 0), sym))
    canvas.alpha_composite(edge)

    return canvas.resize((size, size), Image.LANCZOS)


for name, size in DENSITIES.items():
    render(size).save(f"{BASE}/mipmap-{name}/ic_launcher.png")
    print(f"{name} {size}")

render(BIG).save(f"{BASE}/drawable/ic_launcher_foreground.png")
render(BIG).save("../docs/icon_v7.png")
print("done")
