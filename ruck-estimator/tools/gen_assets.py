#!/usr/bin/env python3
"""Generate the 80s-style assets for Ruck Load.

Dot-matrix bitmap fonts (BMFont .fnt + .png), the walking rucker sprite and
the launcher icon, scaled per screen resolution. Re-run after editing glyphs:

    python3 tools/gen_assets.py

AMOLED (fenix 8 / epix): glyphs are separated "LED" dots with a gap between
them, which lights ~30% fewer pixels. MIP (fenix 7 / fenix 8 Solar): solid
glyphs, because a reflective screen needs every bit of ink density.

The walking rucker sprite is drawn in code (RuckView.SPRITE_*) so it can use
the theme's ink colour on both black and white MIP backgrounds.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..")

# 5x7 dot-matrix glyphs ('#' = lit). Narrow glyphs keep their own width.
GLYPHS = {
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    ":": [".", "#", "#", ".", "#", "#", "."],
    ".": [".", ".", ".", ".", ".", "#", "#"],
    "-": ["....", "....", "....", "####", "....", "....", "...."],
    "/": [".....", "....#", "...#.", "..#..", ".#...", "#....", "....."],
    "%": ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"],
    " ": ["...", "...", "...", "...", "...", "...", "..."],
    "!": ["#", "#", "#", "#", "#", ".", "#"],
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
}

# Launcher icon art (same rucker as RuckView's sprite). G = body, A = pack
ICON_SPRITE = [
    ".....GG...",
    ".....GG...",
    "..AA.G....",
    ".AAAGGG...",
    ".AAAGGGG..",
    ".AAAGG..G.",
    "..AAGG....",
    "....GG....",
    "...G..G...",
    "...G...G..",
    "..G....G..",
    "..G.....G.",
]
ICON_COLORS = {"G": (0, 255, 0, 255), "A": (255, 170, 0, 255)}

# Dot size per screen width: (value-big, value-medium, label). Budgets:
# medium must fit "88:88" (26 dots) in 44% of the width for half-screen
# fields; the full-screen stack (sprite, 5 label rows, big, medium, 13 gaps)
# must fit in ~88% of the height.
SCALES = {
    240: (5, 4, 2),
    260: (6, 4, 2),
    280: (8, 4, 2),
    390: (8, 6, 3),
    416: (10, 7, 3),
    454: (12, 7, 3),
}
AMOLED = {"epix2", "epix2pro42mm", "epix2pro47mm", "fenix843mm",
          "fenix847mm", "fenix8pro47mm"}
DEVICES = {
    "epix2": 416,
    "epix2pro42mm": 390,
    "epix2pro47mm": 416,
    "fenix7": 260,
    "fenix7pro": 260,
    "fenix7pronowifi": 260,
    "fenix7s": 240,
    "fenix7spro": 240,
    "fenix7x": 280,
    "fenix7xpro": 280,
    "fenix843mm": 416,
    "fenix847mm": 454,
    "fenix8pro47mm": 454,
    "fenix8solar47mm": 260,
    "fenix8solar51mm": 280,
}
ICON_SIZES = {"fenix843mm": 60, "fenix847mm": 65, "fenix8pro47mm": 65,
              "epix2": 60, "epix2pro42mm": 60, "epix2pro47mm": 60}


def dot_gap(p, amoled):
    # Separated LED dots on AMOLED once big enough to read as dots
    return 0 if (not amoled or p < 4) else max(1, p // 4)


def write_font(folder, name, p, amoled):
    """Write <name>.fnt/.png: glyphs of p x p dots, 1 dot letter spacing."""
    gap = dot_gap(p, amoled)
    h = 7 * p
    chars = sorted(GLYPHS.items(), key=lambda kv: ord(kv[0]))
    total_w = sum((len(g[0]) + 1) * p for _, g in chars)
    img = Image.new("RGBA", (total_w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = []
    x = 0
    for ch, rows in chars:
        cols = len(rows[0])
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    x0 = x + rx * p
                    y0 = ry * p
                    d.rectangle([x0, y0, x0 + p - 1 - gap, y0 + p - 1 - gap],
                                fill=(255, 255, 255, 255))
        adv = (cols + 1) * p
        lines.append(
            f"char id={ord(ch)} x={x} y=0 width={cols * p} height={h} "
            f"xoffset=0 yoffset=0 xadvance={adv} page=0 chnl=15"
        )
        x += adv
    img.save(os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, f"{name}.fnt"), "w") as f:
        f.write(
            f'info face="{name}" size={h} bold=0 italic=0 charset="" unicode=1 '
            f"stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0\n"
            f"common lineHeight={h} base={h} scaleW={total_w} scaleH={h} "
            f"pages=1 packed=0\n"
            f'page id=0 file="{name}.png"\n'
            f"chars count={len(chars)}\n" + "\n".join(lines) + "\n"
        )


def icon_image(size):
    # Sprite centred on a black disc, nearest-neighbour so it stays pixel-crisp
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, size - 1, size - 1], fill=(0, 0, 0, 255))
    p = max(1, int(size * 0.62) // 12)
    ox = (size - len(ICON_SPRITE[0]) * p) // 2
    oy = (size - len(ICON_SPRITE) * p) // 2
    d = ImageDraw.Draw(img)
    for ry, row in enumerate(ICON_SPRITE):
        for rx, c in enumerate(row):
            if c in ICON_COLORS:
                x0, y0 = ox + rx * p, oy + ry * p
                d.rectangle([x0, y0, x0 + p - 1, y0 + p - 1], fill=ICON_COLORS[c])
    return img


# Value-font ladder for part-screen fields: every dot size from big down to
# one above the label, largest first, padded with the smallest so every
# device has the same resource ids (V0..V8). The view loads only the rung
# that fits the field, so unused rungs cost PRG space, not memory.
LADDER = 9
DIGITS = "0123456789:.-%/ "
# Big/medium also carry the letters of the start screen ("RUCK", "READY",
# "GO!"), nothing more, to keep them small
TITLE = DIGITS + "ACDEGKORUY!"


def font_line(font_id, file, filt_chars):
    filt = f' filter="{filt_chars}"' if filt_chars else ""
    return (f'    <font id="{font_id}" filename="{file}.fnt" '
            f'antialias="false"{filt} />\n')


def ladder(big, label):
    sizes = list(range(big, label, -1))[:LADDER]
    return sizes + [sizes[-1]] * (LADDER - len(sizes))
DRAWABLES_XML = """<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png" />
</drawables>
"""


def write_set(res_dir, width, icon_size, amoled):
    big, med, label = SCALES[width]
    fonts = os.path.join(res_dir, "fonts")
    draw = os.path.join(res_dir, "drawables")
    os.makedirs(fonts, exist_ok=True)
    os.makedirs(draw, exist_ok=True)
    write_font(fonts, "big", big, amoled)
    write_font(fonts, "medium", med, amoled)
    write_font(fonts, "label", label, amoled)
    xml = [font_line("Big", "big", TITLE), font_line("Medium", "medium", TITLE),
           font_line("Label", "label", None)]
    for i, p in enumerate(ladder(big, label)):
        write_font(fonts, f"v{i}", p, amoled)
        xml.append(font_line(f"V{i}", f"v{i}", DIGITS))
    with open(os.path.join(fonts, "fonts.xml"), "w") as f:
        f.write("<fonts>\n" + "".join(xml) + "</fonts>\n")
    icon_image(icon_size).save(os.path.join(draw, "launcher_icon.png"))
    with open(os.path.join(draw, "drawables.xml"), "w") as f:
        f.write(DRAWABLES_XML)


def main():
    write_set(os.path.join(ROOT, "resources"), 260, 40, False)
    for dev, width in DEVICES.items():
        write_set(os.path.join(ROOT, f"resources-{dev}"), width,
                  ICON_SIZES.get(dev, 40), dev in AMOLED)


if __name__ == "__main__":
    main()
