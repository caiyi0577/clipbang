"""生成拟物版启动图标：带投影、高光、刻痕的剪贴板，浮在渐变底座上"""
from PIL import Image, ImageDraw, ImageFilter

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
BASE = "app/src/main/res"
VIEW = 108.0
BIG = 432


def lerp(a, b, t):
    return int(round(a + (b - a) * t))


def vgrad(size, top, bottom):
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        img.putpixel((0, y), (lerp(top[0], bottom[0], t),
                              lerp(top[1], bottom[1], t),
                              lerp(top[2], bottom[2], t)))
    return img.resize((size, size))


def shadow(layer, box, radius, blur, alpha, offset):
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    b = [box[0] + offset[0], box[1] + offset[1], box[2] + offset[0], box[3] + offset[1]]
    d.rounded_rectangle(b, radius=radius, fill=(0, 0, 0, alpha))
    return Image.alpha_composite(layer, sh.filter(ImageFilter.GaussianBlur(blur)))


def draw_foreground(size):
    s = size / VIEW
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    def px(v):
        return int(round(v * s))

    board = [px(26), px(30), px(62), px(82)]
    clipb = [px(38), px(24), px(54), px(33)]
    radius = max(1, int(2.4 * s))

    layer = shadow(layer, board, radius, 3.2 * s, 70, (0, int(3.4 * s)))
    layer = shadow(layer, clipb, max(1, radius // 2), 2.0 * s, 55, (0, int(1.6 * s)))

    for (x, y, w, a) in [(68, 32, 9, 255), (78, 47, 6, 217), (68, 60, 8, 242)]:
        layer = shadow(layer, [px(x), px(y), px(x + w), px(y + w)], max(1, int(1.2 * s)),
                       1.6 * s, 34, (0, int(1.2 * s)))

    face = vgrad(size, (255, 255, 255), (238, 238, 238)).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(board, radius=radius, fill=255)
    layer.paste(face, (0, 0), mask)

    d = ImageDraw.Draw(layer)
    d.line([board[0] + radius, board[1] + max(1, int(0.5 * s)),
            board[2] - radius, board[1] + max(1, int(0.5 * s))],
           fill=(255, 255, 255, 255), width=max(1, int(0.9 * s)))
    d.line([board[0] + radius, board[3] - max(1, int(0.9 * s)),
            board[2] - radius, board[3] - max(1, int(0.9 * s))],
           fill=(214, 214, 214, 255), width=max(1, int(0.9 * s)))

    clip_img = vgrad(size, (238, 238, 238), (211, 211, 211)).convert("RGBA")
    m2 = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m2).rounded_rectangle(clipb, radius=max(1, radius // 2), fill=255)
    layer.paste(clip_img, (0, 0), m2)
    d = ImageDraw.Draw(layer)
    d.line([clipb[0] + 2, clipb[1] + max(1, int(0.6 * s)),
            clipb[2] - 2, clipb[1] + max(1, int(0.6 * s))],
           fill=(255, 255, 255, 255), width=max(1, int(0.8 * s)))

    for (x1, y1, x2) in [(32, 42, 54), (32, 53, 54), (32, 64, 46)]:
        top = [px(x1), px(y1), px(x2), px(y1 + 5)]
        d.rounded_rectangle(top, radius=max(1, int(0.9 * s)), fill=(58, 92, 176, 255))
        d.line([top[0] + 2, top[1] + max(1, int(0.5 * s)),
                top[2] - 2, top[1] + max(1, int(0.5 * s))],
               fill=(120, 158, 235, 170), width=max(1, int(0.6 * s)))

    for (x, y, w, a) in [(68, 32, 9, 255), (78, 47, 6, 217), (68, 60, 8, 242)]:
        b = [px(x), px(y), px(x + w), px(y + w)]
        d.rounded_rectangle(b, radius=max(1, int(0.8 * s)), fill=(255, 255, 255, a))
        d.line([b[0] + 1, b[1] + max(1, int(0.5 * s)), b[2] - 1, b[1] + max(1, int(0.5 * s))],
               fill=(255, 255, 255, 255), width=max(1, int(0.7 * s)))

    return layer


def draw_background(size):
    img = vgrad(size, (0x6E, 0x95, 0xEF), (0x3F, 0x64, 0xBE)).convert("RGBA")

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-size * 0.25, -size * 0.62, size * 1.25, size * 0.42],
               fill=(255, 255, 255, 34))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(size * 0.1)))

    dark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(dark).rectangle([0, size * 0.72, size, size], fill=(0, 0, 0, 26))
    return Image.alpha_composite(img, dark.filter(ImageFilter.GaussianBlur(size * 0.06)))


def compose(size):
    bg = draw_background(size)
    fg = draw_foreground(size)

    rounded = Image.new("L", (size, size), 0)
    ImageDraw.Draw(rounded).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * 0.225), fill=255
    )
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), rounded)
    out = Image.alpha_composite(out, fg)

    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.paste(out, (0, 0), rounded)
    return final


for name, size in DENSITIES.items():
    compose(size).save(f"{BASE}/mipmap-{name}/ic_launcher.png")
    print(f"{name} {size}")

draw_foreground(BIG).save(f"{BASE}/drawable/ic_launcher_foreground.png")
compose(BIG).save("../docs/icon_v2.png")
print("done")
