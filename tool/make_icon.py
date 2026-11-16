"""Draws the StackSpace logo in the Sky Classic style: three stacked layers in a
glowing sky-blue gradient outline on a dark graphite rounded tile.

Run from the repository root with Pillow installed:
    python tool/make_icon.py out
Writes logo_1024.png, logo_512.png, logo_256.png and app_icon.ico (16 to 256 px) into the
given folder. Copy app_icon.ico to windows/runner/resources/, logo_256.png to
assets/branding/logo.png and logo_1024.png to assets/branding/logo_1024.png.

The small icon sizes (48 px and under) are drawn separately with thicker strokes
and a tighter glow, so the layers stay readable in the taskbar and title bar.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024
TILE_TOP = (52, 54, 59)      # #34363b
TILE_BOTTOM = (30, 31, 34)   # #1e1f22
RIM = (69, 72, 79)           # #45484f
SKY_A = (61, 139, 255)       # #3d8bff, Graphite folder gradient start
SKY_B = (140, 196, 255)      # #8cc4ff, Graphite folder gradient end

# The mark: a diamond (top layer) and two chevrons under it, in 1024 units.
TOP = [(512, 220), (812, 380), (512, 540), (212, 380), (512, 220)]
MID = [(212, 520), (512, 680), (812, 520)]
LOW = [(212, 660), (512, 820), (812, 660)]


def vertical(c1, c2):
    g = Image.new('RGB', (1, S))
    for y in range(S):
        t = y / (S - 1)
        g.putpixel((0, y), tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return g.resize((S, S))


def diagonal(c1, c2):
    # Top left to bottom right, as in the Sky Classic icon.
    small = Image.new('RGB', (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return small.resize((S, S), Image.BILINEAR)


def tile_mask(inset=0):
    m = Image.new('L', (S, S), 0)
    r = int(S * 0.215)
    ImageDraw.Draw(m).rounded_rectangle((24 + inset, 24 + inset, S - 25 - inset, S - 25 - inset),
                                        radius=r - inset, fill=255)
    return m


def mark_mask(width):
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    for line in (TOP, MID, LOW):
        d.line(line, fill=255, width=width, joint='curve')
        # Round caps and corners.
        for x, y in line:
            d.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=255)
    return m


def build(width=60, glow_blur=30, glow_strength=235):
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    tile = tile_mask()
    out.paste(vertical(TILE_TOP, TILE_BOTTOM), (0, 0), tile)
    # A thin light rim, like the Sky Classic tile's stroke.
    rim = ImageChops.subtract(tile, tile_mask(12))
    rim_layer = Image.new('RGBA', (S, S), RIM + (255,))
    out.paste(rim_layer, (0, 0), rim)
    sky = diagonal(SKY_A, SKY_B)
    mark = mark_mask(width)
    # Soft sky glow behind the mark, kept inside the tile.
    glow_a = mark.filter(ImageFilter.GaussianBlur(glow_blur))
    glow_a = ImageChops.multiply(glow_a, tile).point(lambda v: v * glow_strength // 255)
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    glow.paste(sky, (0, 0), glow_a)
    out = Image.alpha_composite(out, glow)
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    layer.paste(sky, (0, 0), mark)
    return Image.alpha_composite(out, layer)


def small(size):
    # Thicker strokes for the taskbar sizes.
    width = 96 if size <= 24 else 80
    return build(width=width, glow_blur=18, glow_strength=120).resize((size, size), Image.LANCZOS)


if __name__ == '__main__':
    folder = sys.argv[1]
    img = build()
    img.save(folder + '/logo_1024.png')
    for s in (256, 512):
        img.resize((s, s), Image.LANCZOS).save(folder + f'/logo_{s}.png')
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = [small(s) if s <= 48 else img.resize((s, s), Image.LANCZOS) for s in sizes]
    frames[-1].save(folder + '/app_icon.ico', sizes=[(s, s) for s in sizes], append_images=frames[:-1])
