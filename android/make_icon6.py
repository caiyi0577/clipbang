"""
启动图标：锤子时钟那种轻拟物。
白色圆角方块上挖一个圆形深槽，槽里放一块白板，板上是炸开的字块。
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


def circle_mask(size, cx, cy, r):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return m


def shade(size, mask, color, blur):
    """把一层颜色按遮罩压上去，再做模糊当阴影用"""
    lay = Image.new("RGBA", size, (0, 0, 0, 0))
    lay.paste(Image.new("RGBA", size, color), (0, 0), mask)
    return lay.filter(ImageFilter.GaussianBlur(blur))


def render(size):
    S = int(size * SUPER)
    u = S / VIEW
    cx = cy = S / 2.0

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # ---------- 白色方块 ----------
    shell = [0, 0, S - 1, S - 1]
    outer = rr_mask(S, shell, int(S * 0.235))

    # 落在地上的投影
    ground = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ground).rounded_rectangle(
        [u * 3, u * 6, S - u * 3, S - u * 1], radius=int(S * 0.235), fill=(74, 74, 80, 95)
    )
    canvas.alpha_composite(ground.filter(ImageFilter.GaussianBlur(u * 3.0)))

    face = vgrad(S, S, (255, 255, 255), (238, 238, 238)).convert("RGBA")
    canvas.paste(face, (0, 0), outer)

    # 方块自身的边界线，白底白块不加这条会消失
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(shell, radius=int(S * 0.235),
                        outline=(214, 214, 218, 255), width=max(1, int(u * 0.55)))
    # 顶边一道高光，底边一道暗线
    d.arc([u * 5, u * 4, S - u * 5, S - u * 4], start=196, end=344,
          fill=(255, 255, 255, 235), width=max(1, int(u * 0.9)))
    d.arc([u * 5, u * 4, S - u * 5, S - u * 4], start=20, end=160,
          fill=(214, 214, 216, 150), width=max(1, int(u * 0.9)))

    # ---------- 圆形凹槽 ----------
    slot_r = u * 33.5

    # 槽口的暗影压在内壁上沿
    rim = circle_mask(S, cx, cy, slot_r + u * 1.2)
    inner_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    isd = ImageDraw.Draw(inner_shadow)
    isd.ellipse([cx - slot_r - u * 1.2, cy - slot_r - u * 2.2,
                 cx + slot_r + u * 1.2, cy + slot_r + u * 0.6],
                fill=(0, 0, 0, 95))
    inner_shadow = inner_shadow.filter(ImageFilter.GaussianBlur(u * 1.5))
    inner_shadow.putalpha(Image.composite(inner_shadow.getchannel("A"),
                                          Image.new("L", (S, S), 0), rim))
    canvas.alpha_composite(inner_shadow)

    dial = vgrad(S, S, (0x4A, 0x4C, 0x50), (0x2B, 0x2D, 0x31)).convert("RGBA")
    canvas.paste(dial, (0, 0), circle_mask(S, cx, cy, slot_r))

    # 槽壁下沿的反光，凹槽才有深度
    d = ImageDraw.Draw(canvas)
    d.arc([cx - slot_r, cy - slot_r, cx + slot_r, cy + slot_r],
          start=18, end=162, fill=(150, 152, 158, 90), width=max(1, int(u * 0.8)))

    # ---------- 盘面内容 ----------
    # 不放白板，字块直接坐在深色盘上，结构更接近参考里"深盘 + 内容"的关系
    base_y = cy + u * 1.0

    blocks = [
        (-15.5, -12.0, 8.0, 7.0),
        (-5.5, -12.0, 7.0, 7.0),
        (3.5, -12.0, 5.5, 7.0),
        (-15.5, -3.0, 6.0, 7.0),
        (-7.5, -3.0, 8.0, 7.0),
        (2.5, -3.0, 6.5, 7.0),
        (-15.5, 6.0, 9.0, 7.0),
        (-4.5, 6.0, 5.5, 7.0),
    ]
    for (bx, by, bw, bh) in blocks:
        x1 = cx + u * bx
        y1 = base_y + u * by
        d.rounded_rectangle(
            [x1, y1, x1 + u * bw, y1 + u * bh],
            radius=u * 1.6,
            fill=(0x8F, 0xB2, 0xF7, 255)
        )

    # 飞出去的三块
    shards = [(11.5, 4.5, 6.6, 250), (18.5, -2.5, 5.4, 210), (16.5, 12.0, 4.6, 180)]
    for (sx, sy, s2, a) in shards:
        x1 = cx + u * sx
        y1 = base_y + u * sy
        d.rounded_rectangle(
            [x1, y1, x1 + u * s2, y1 + u * s2],
            radius=u * 1.0,
            fill=(0x8F, 0xB2, 0xF7, a)
        )

    return canvas.resize((size, size), Image.LANCZOS)


for name, size in DENSITIES.items():
    render(size).save(f"{BASE}/mipmap-{name}/ic_launcher.png")
    print(f"{name} {size}")

render(BIG).save(f"{BASE}/drawable/ic_launcher_foreground.png")
render(BIG).save("../docs/icon_v6.png")
print("done")
