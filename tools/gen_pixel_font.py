#!/usr/bin/env python3
"""Generate the 8-bit style "Pixel" bitmap fonts used by the data field.

Glyphs are original 5x7 designs (below), rendered at integer scales into
AngelCode BMFont text files + greyscale PNGs, the format monkeyc compiles.

Two sets are generated:
  PixelN - solid glyphs, used on MIP (fenix 7). On a reflective panel any
           gap between glyph pixels only costs contrast, and MIP power does
           not depend on how many pixels are lit.
  DotN   - dot-matrix glyphs (1px gutter around each glyph pixel), used on
           AMOLED (fenix 8 / epix). Lights ~40% fewer pixels: less power and
           less burn-in, and it reads as an LED matrix on an emissive panel.

Run from the repo root:  python3 tools/gen_pixel_font.py
"""
import os
from PIL import Image

OUT_DIR = os.path.join("resources", "fonts")
SCALES = range(2, 11)  # Pixel2 .. Pixel10; the view picks what fits at runtime
DOT_SCALES = range(4, 11)  # below 4 a gutter would eat the glyph
ROWS = 7

G = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["111", "010", "010", "010", "010", "010", "111"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    ":": ["0", "1", "1", "0", "1", "1", "0"],
    ".": ["0", "0", "0", "0", "0", "1", "1"],
    ",": ["00", "00", "00", "00", "00", "01", "10"],
    "-": ["0000", "0000", "0000", "1111", "0000", "0000", "0000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "!": ["1", "1", "1", "1", "1", "0", "1"],
    "?": ["01110", "10001", "00001", "00110", "00100", "00000", "00100"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    "'": ["1", "1", "0", "0", "0", "0", "0"],
    "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
    " ": ["00", "00", "00", "00", "00", "00", "00"],
    # '^' renders a check mark (reached milestone)
    "^": ["00000", "00001", "00011", "10110", "11100", "01000", "00000"],
}


def render(scale, dotted):
    gutter = 1 if dotted else 0
    height = ROWS * scale
    pad = 1
    chars = sorted(G.items(), key=lambda kv: ord(kv[0]))
    sheet_w = sum(len(rows[0]) * scale + pad for _, rows in chars) + pad
    img = Image.new("L", (sheet_w, height + 2 * pad), 0)
    px = img.load()
    lines = []
    x = pad
    for ch, rows in chars:
        cols = len(rows[0])
        for r, row in enumerate(rows):
            for c, bit in enumerate(row):
                if bit != "1":
                    continue
                for dy in range(scale - gutter):
                    for dx in range(scale - gutter):
                        px[x + c * scale + dx, pad + r * scale + dy] = 255
        w = cols * scale
        lines.append(
            f"char id={ord(ch)} x={x} y={pad} width={w} height={height} "
            f"xoffset=0 yoffset=0 xadvance={w + scale} page=0 chnl=15"
        )
        x += w + pad

    name = f"{'dot' if dotted else 'pixel'}{scale}"
    img.save(os.path.join(OUT_DIR, f"{name}.png"))
    with open(os.path.join(OUT_DIR, f"{name}.fnt"), "w") as f:
        f.write(
            f'info face="Pixel" size={height} bold=0 italic=0 charset="" '
            f"unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n"
            f"common lineHeight={height} base={height} scaleW={img.width} "
            f"scaleH={img.height} pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0\n"
            f'page id=0 file="{name}.png"\n'
            f"chars count={len(lines)}\n" + "\n".join(lines) + "\n"
        )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for s in SCALES:
        render(s, False)
    for s in DOT_SCALES:
        render(s, True)
    with open(os.path.join(OUT_DIR, "fonts.xml"), "w") as f:
        f.write("<!-- Generated by tools/gen_pixel_font.py -->\n<fonts>\n")
        for s in SCALES:
            f.write(f'    <font id="Pixel{s}" filename="pixel{s}.fnt" antialias="false" />\n')
        for s in DOT_SCALES:
            f.write(f'    <font id="Dot{s}" filename="dot{s}.fnt" antialias="false" />\n')
        f.write("</fonts>\n")


if __name__ == "__main__":
    main()
