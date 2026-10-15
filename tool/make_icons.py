"""Generates app icons and splash images for Nomo from the brand mark geometry.

Run: python3 tool/make_icons.py   (needs Pillow)
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "brand"
BLACK, WHITE, GOLD = (10, 10, 10, 255), (255, 255, 255, 255), (255, 201, 60, 255)
SS = 4  # supersampling


def mark_points():
    pts = []
    for i in range(0, 35):  # left leg 84 → 50
        pts.append((24, 84 - i))
    for i in range(0, 181):  # arch over the top
        a = math.radians(180 - i)
        pts.append((50 + 26 * math.cos(a), 50 - 26 * math.sin(a)))
    for i in range(0, 35):  # right leg 50 → 84
        pts.append((76, 50 + i))
    return pts


def draw_mark(img, x, y, size, ink, dot):
    d = ImageDraw.Draw(img)
    s = size / 100
    r = 7.5 * s
    for px, py in mark_points():
        cx, cy = x + px * s, y + py * s
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ink)
    cx, cy, rr = x + 50 * s, y + 68 * s, 9 * s
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=dot)


def render(name, size, bg, ink, dot, mark_frac, mark_y_shift=0.0):
    big = size * SS
    img = Image.new("RGBA", (big, big), bg)
    m = big * mark_frac
    x = (big - m) / 2
    y = (big - m) / 2 + big * mark_y_shift
    draw_mark(img, x, y, m, ink, dot)
    img = img.resize((size, size), Image.LANCZOS)
    if bg[3] == 255:
        img = img.convert("RGB")
    img.save(OUT / name)
    print("wrote", OUT / name)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    clear = (0, 0, 0, 0)
    # iOS / legacy icons: full-bleed, no transparency.
    render("icon-passenger-1024.png", 1024, BLACK, WHITE, GOLD, 0.56, 0.0)
    render("icon-driver-1024.png", 1024, GOLD, BLACK, BLACK, 0.56, 0.0)
    # Android adaptive foregrounds: mark inside the 66% safe zone.
    render("icon-passenger-foreground.png", 1024, clear, WHITE, GOLD, 0.40, 0.0)
    render("icon-driver-foreground.png", 1024, clear, BLACK, BLACK, 0.40, 0.0)
    # Splash marks on transparent background.
    render("splash-mark.png", 768, clear, WHITE, GOLD, 0.5, 0.0)
    render("splash-mark-dark.png", 768, clear, BLACK, WHITE, 0.5, 0.0)
    # Store feature graphic helper (Google Play needs 1024×500).
    fg = Image.new("RGB", (1024 * SS, 500 * SS), BLACK[:3])
    draw_mark(fg, 120 * SS, 120 * SS, 260 * SS, WHITE, GOLD)
    fg = fg.resize((1024, 500), Image.LANCZOS)
    fg.save(OUT / "play-feature-graphic-base.png")
    print("wrote", OUT / "play-feature-graphic-base.png")
