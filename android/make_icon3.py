"""
拟物 3D 风格启动图标：橙色厚底板上叠着几张白纸，蓝色夹子压住纸叠，整体轻微右倾。
超采样绘制再缩小，避免旋转边缘发虚。
"""
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


def blurred(size, box, radius, color, blur):
    lay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(lay).rounded_rectangle(box, radius=radius, fill=color)
    return lay.filter(ImageFilter.GaussianBlur(blur))


def render(size):
    S = int(size * SUPER)
    u = S / VIEW

    def p(v):
        return v * u

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # ---------- 橙色底板 ----------
    # 底面（厚度），往右下挤出来一截
    canvas = Image.alpha_composite(
        canvas,
        blurred(S, [p(13), p(20), p(95), p(102)], p(13), (138, 70, 14, 255), p(0.8))
    )

    # 外投影，让整块板从背景里浮出来
    canvas = Image.alpha_composite(
        canvas,
        blurred(S, [p(12), p(18), p(96), p(98)], p(14), (120, 60, 10, 90), p(2.6))
    )

    board = vgrad(S, S, (0xFF, 0xB4, 0x52), (0xE0, 0x7A, 0x1C)).convert("RGBA")
    canvas.paste(board, (0, 0), rr_mask(S, [p(13), p(13), p(95), p(95)], p(13)))

    d = ImageDraw.Draw(canvas)
    # 板顶一条高光，板底一条暗边
    d.rounded_rectangle([p(15), p(14.2), p(93), p(96)], radius=p(11),
                        outline=(255, 216, 160, 120), width=max(1, int(p(0.9))))

    # ---------- 纸叠 ----------
    # 纸的影子落在板上
    canvas = Image.alpha_composite(
        canvas,
        blurred(S, [p(26), p(33), p(86), p(90)], p(4), (120, 55, 10, 110), p(2.2))
    )

    sheets = [
        ([p(25), p(36), p(85), p(92)], (0xDD, 0xDD, 0xDD)),
        ([p(24), p(33), p(86), p(90)], (0xEF, 0xEF, 0xEF)),
        ([p(23), p(30), p(87), p(88)], (0xFF, 0xFF, 0xFF)),
    ]
    for box, color in sheets:
        canvas = Image.alpha_composite(
            canvas,
            blurred(S, [box[0], box[1] + p(1.5), box[2], box[3] + p(1.5)],
                    p(3.2), (110, 50, 8, 80), p(1.0))
        )
        face = vgrad(S, S, color, tuple(min(255, c - 8) for c in color)).convert("RGBA")
        canvas.paste(face, (0, 0), rr_mask(S, box, p(3.2)))

    d = ImageDraw.Draw(canvas)
    # 最上面那张纸的边线，压出层次
    d.rounded_rectangle([p(23), p(30), p(87), p(88)], radius=p(3.2),
                        outline=(226, 226, 226, 200), width=max(1, int(p(0.6))))

    # ---------- 蓝色夹子 ----------
    canvas = Image.alpha_composite(
        canvas,
        blurred(S, [p(37), p(28), p(71), p(50)], p(7), (24, 60, 112, 135), p(1.8))
    )

    clip = vgrad(S, S, (0x63, 0xAD, 0xF8), (0x2C, 0x74, 0xCE)).convert("RGBA")
    canvas.paste(clip, (0, 0), rr_mask(S, [p(37), p(20), p(71), p(47)], p(8)))

    # 夹子顶部的受光面
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.rounded_rectangle([p(40.5), p(22.5), p(67.5), p(31)], radius=p(4.5), fill=(255, 255, 255, 120))
    canvas.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(p(0.8))))

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([p(37), p(20), p(71), p(47)], radius=p(8),
                        outline=(28, 86, 158, 200), width=max(1, int(p(0.6))))

    # ---------- 轻微右倾 ----------
    tilt = canvas.rotate(-7, resample=Image.BICUBIC, center=(S / 2, S / 2))

    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(tilt)
    return out.resize((size, size), Image.LANCZOS)


for name, size in DENSITIES.items():
    render(size).save(f"{BASE}/mipmap-{name}/ic_launcher.png")
    print(f"{name} {size}")

render(BIG).save(f"{BASE}/drawable/ic_launcher_foreground.png")
render(BIG).save("../docs/icon_v3.png")
print("done")
