"""Builds the cards' paper grain from a 768x384 screenshot of Tools/portfolio_noise.html.

That page renders the portfolio site's grain (feTurbulence fractalNoise, baseFrequency
0.65, 2 octaves, at 20%) at @3x, so a 128 pt tile has the site's grain size. Only the
left (light) 384 px square is used.

The output (Assets: CardGrain) is the grain at GAIN times the site's strength,
baked into the card grey (Theme.card: 234 light, 28 dark) as an opaque grayscale
tile, centred on the card grey so the card keeps its tone. Nothing is blended at
runtime: the card's fill is just this tile.

Usage (from app/): python3 -I Tools/import_portfolio_grain.py <screenshot.png> Vocab/Assets.xcassets
"""
import os, struct, sys, zlib

# The grain's strength, in multiples of the site's grain.
GAIN = 0.8

CONTENTS = """{
  "images" : [
    { "filename" : "light.png", "idiom" : "universal", "scale" : "3x" },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "dark.png", "idiom" : "universal", "scale" : "3x"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""


def png_gray(n, px):
    raw = b"".join(b"\x00" + bytes(row) for row in px)
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def read_png(path):
    data = open(path, "rb").read()
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n, t = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if t == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and interlace == 0 and ctype in (2, 6), (depth, ctype, interlace)
            bpp = 3 if ctype == 2 else 4
        elif t == b"IDAT":
            idat += body
        pos += 12 + n
    raw, stride, rows, prev = zlib.decompress(idat), w * bpp, [], bytearray(w * bpp)
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    return [[row[x * bpp] for x in range(w)] for row in rows]  # red channel: the noise is grey


shot, catalog = sys.argv[1], sys.argv[2]
px = read_png(shot)
N = 384
light = [row[:N] for row in px[:N]]
mean = sum(map(sum, light)) / N / N

d = os.path.join(catalog, "CardGrain.imageset")
os.makedirs(d, exist_ok=True)
# The dark card is grey too, so its grain can go both ways: the same grain around it.
for name, base in (("light.png", 234), ("dark.png", 28)):
    tile = [[max(0, min(255, round(base + (v - mean) * GAIN))) for v in row] for row in light]
    data = png_gray(N, tile)
    open(os.path.join(d, name), "wb").write(data)
    vals = [v for row in tile for v in row]
    print(f"{name}: {len(data) / 1024:.1f} KB, mean {sum(vals) / len(vals):.2f}, range {min(vals)}-{max(vals)}")
open(os.path.join(d, "Contents.json"), "w").write(CONTENTS)
