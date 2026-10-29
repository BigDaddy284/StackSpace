"""Draws the StackSpace logo: the accent-gradient layers mark on a dark rounded tile.

Run from the repository root with Pillow installed:
    python tool/make_icon.py out
Writes logo_1024.png, logo_512.png, logo_256.png and app_icon.ico (16 to 256 px) into the
given folder. Copy app_icon.ico to windows/runner/resources/, logo_256.png to
assets/branding/logo.png and logo_1024.png to assets/branding/logo_1024.png.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024
A = (38, 104, 255)   # theme accentA
B = (176, 72, 255)   # theme accentB

def gradient(size, c1, c2):
    # Diagonal gradient, top left to bottom right, as in the app's accent.
    w, h = size
    g = Image.new('RGB', (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = (x + y) / (w + h - 2)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return g

def lin_gradient_small(c1, c2):
    return gradient((256, 256), c1, c2).resize((S, S), Image.BILINEAR)

def vertical(c1, c2, y0, y1):
    g = Image.new('RGB', (1, S))
    for y in range(S):
        t = min(1, max(0, (y - y0) / (y1 - y0)))
        g.putpixel((0, y), tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return g.resize((S, S))

def tile_mask(inset=0):
    m = Image.new('L', (S, S), 0)
    r = int(S * 0.225)
    ImageDraw.Draw(m).rounded_rectangle((inset, inset, S - 1 - inset, S - 1 - inset), radius=r - inset, fill=255)
    return m

def glyph_mask():
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    cx, hw, hh, step, w = 512, 270, 154, 126, 62
    top = 512 - (hh * 2 + step * 2 + w // 2) // 2 + 4
    cy = top + hh
    d.polygon([(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)], fill=255)
    for k in (1, 2):
        o = step * k
        pts = [(cx - hw, cy + o), (cx, cy + hh + o), (cx + hw, cy + o)]
        d.line(pts, fill=255, width=w, joint='curve')
        for p in (pts[0], pts[2]):
            d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=255)
    return m

def build():
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # Dark tile with a soft vertical shade.
    bg = gradient((64, 64), (30, 30, 44), (12, 12, 18)).resize((S, S), Image.BILINEAR)
    tile = tile_mask()
    out.paste(bg, (0, 0), tile)
    # Accent rim: the gradient, kept only on a thin ring at the tile edge.
    rim = ImageChops.subtract(tile, tile_mask(10))
    acc = lin_gradient_small(A, B)
    rim_layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    rim_layer.paste(acc, (0, 0), rim.point(lambda v: v * 150 // 255))
    out = Image.alpha_composite(out, rim_layer)
    # Glow behind the glyph, clipped to the tile.
    g = glyph_mask()
    glow_a = g.filter(ImageFilter.GaussianBlur(48)).point(lambda v: min(255, v * 2))
    glow_a = ImageChops.multiply(glow_a, tile)
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    glow.paste(vertical(A, B, g.getbbox()[1], g.getbbox()[3]), (0, 0), glow_a.point(lambda v: v * 200 // 255))
    out = Image.alpha_composite(out, glow)
    # The glyph itself, accent gradient with a light top lift.
    y0, y1 = g.getbbox()[1], g.getbbox()[3]
    bright = vertical((70, 140, 255), (190, 100, 255), y0, y1)
    glyph = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    glyph.paste(bright, (0, 0), g)
    out = Image.alpha_composite(out, glyph)
    return out

img = build()
img.save(sys.argv[1] + '/logo_1024.png')
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
img.save(sys.argv[1] + '/app_icon.ico', sizes=[(s, s) for s in sizes])
for s in (256, 512):
    img.resize((s, s), Image.LANCZOS).save(sys.argv[1] + f'/logo_{s}.png')
