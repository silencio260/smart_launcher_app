from pathlib import Path
from shutil import copy2
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app promotional assets" / "v2"
FINALS = OUT / "finals"
SOURCES = OUT / "source-examples"
PROMPTS = OUT / "prompts"

ORANGE = (255, 93, 25)
YELLOW = (255, 198, 40)
CYAN = (24, 189, 225)
BLUE = (63, 104, 255)
PINK = (255, 75, 154)
PURPLE = (126, 91, 255)
GREEN = (31, 203, 127)
BLACK = (20, 22, 28)
WHITE = (255, 255, 255)
INK = (28, 30, 38)

SCREENSHOTS = {
    "home": ROOT / "templates/App Screenshots/photo_2026-05-03 11.53.37 PM.jpeg",
    "home_clean": ROOT / "templates/App Screenshots/launcher_discover_search_library/photo_2026-06-02 9.33.25 PM.jpeg",
    "library": ROOT / "templates/App Screenshots/photo_2026-05-03 11.53.45 PM.jpeg",
    "search": ROOT / "templates/App Screenshots/launcher_discover_search_library/photo_2026-06-02 9.46.10 PM.jpeg",
    "privacy": ROOT / "templates/App Screenshots/sub apps/app lock/photo_2026-06-02 10.07.16 AM.jpeg",
    "vault": ROOT / "templates/App Screenshots/sub apps/app lock and file hider/photo_2026-06-02 12.00.06 AM.jpeg",
    "clock": ROOT / "templates/App Screenshots/sub apps/alarm/alarm 2/photo_2026-06-01 11.55.35 PM.jpeg",
    "timer": ROOT / "templates/App Screenshots/sub apps/alarm/alarm 2/photo_2026-06-01 11.55.57 PM.jpeg",
}


def ensure_dirs():
    for folder in (FINALS, SOURCES, PROMPTS):
        folder.mkdir(parents=True, exist_ok=True)


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Users/faruqshabi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/lib/python3.12/site-packages/reportlab/fonts/VeraBd.ttf"
        if bold
        else "/Users/faruqshabi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/lib/python3.12/site-packages/reportlab/fonts/Vera.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except Exception:
            pass
    return ImageFont.load_default()


def fit_font(text, max_width, start, bold=True):
    size = start
    probe = Image.new("RGB", (10, 10))
    d = ImageDraw.Draw(probe)
    while size > 18:
        f = font(size, bold)
        if d.textbbox((0, 0), text, font=f)[2] <= max_width:
            return f
        size -= 2
    return font(size, bold)


def gradient(size, stops):
    w, h = size
    img = Image.new("RGB", size)
    pix = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        scaled = t * (len(stops) - 1)
        i = min(int(scaled), len(stops) - 2)
        tt = scaled - i
        a, b = stops[i], stops[i + 1]
        col = tuple(int(a[c] * (1 - tt) + b[c] * tt) for c in range(3))
        for x in range(w):
            side = x / max(w - 1, 1)
            light = int((side - 0.5) * 18)
            pix[x, y] = tuple(max(0, min(255, v + light)) for v in col)
    return img


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width, im.height), radius=radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im.convert("RGBA"), (0, 0), mask)
    return out


def paste_shadow(base, layer, xy, blur=22, alpha=90, offset=(0, 12)):
    mask = layer.getchannel("A")
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shadow.putalpha(mask.point(lambda p: int(p * alpha / 255)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow, (xy[0] + offset[0], xy[1] + offset[1]))
    base.alpha_composite(layer, xy)


def phone(path, height, crop_bottom=0, rotate=0):
    im = Image.open(path).convert("RGB")
    if crop_bottom:
        im = im.crop((0, 0, im.width, im.height - crop_bottom))
    width = int(height * im.width / im.height)
    im = im.resize((width, height), Image.Resampling.LANCZOS)
    pad = max(5, height // 95)
    radius = max(18, height // 19)
    frame = Image.new("RGBA", (width + pad * 2, height + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, frame.width, frame.height), radius=radius + pad, fill=(9, 10, 15, 255))
    frame.alpha_composite(rounded(im, radius), (pad, pad))
    if rotate:
        frame = frame.rotate(rotate, expand=True, resample=Image.Resampling.BICUBIC)
    return frame


def reflection(layer, max_height=82):
    refl = layer.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    refl = refl.crop((0, 0, refl.width, min(max_height, refl.height)))
    alpha = refl.getchannel("A")
    grad = Image.new("L", refl.size, 0)
    gp = grad.load()
    for y in range(refl.height):
        val = int(82 * (1 - y / max(1, refl.height - 1)))
        for x in range(refl.width):
            gp[x, y] = val
    refl.putalpha(Image.composite(grad, Image.new("L", refl.size, 0), alpha))
    return refl.filter(ImageFilter.GaussianBlur(0.4))


def paste_phone(base, layer, xy, ref=True):
    paste_shadow(base, layer, xy, blur=18, alpha=86, offset=(0, 12))
    if ref:
        base.alpha_composite(reflection(layer), (xy[0], xy[1] + layer.height - 2))


def text_center(draw, box, text, fnt, fill):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    x = box[0] + (box[2] - box[0] - bbox[2] + bbox[0]) / 2
    y = box[1] + (box[3] - box[1] - bbox[3] + bbox[1]) / 2 - 2
    draw.text((x, y), text, font=fnt, fill=fill)


def pill(draw, box, text, fill, stroke=None, text_fill=INK, width=3):
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=fill, outline=stroke, width=width)
    text_center(draw, box, text, font(24, True), text_fill)


def headline(draw, xy, lines, colors, max_width=500):
    x, y = xy
    for i, line in enumerate(lines):
        f = fit_font(line, max_width, 58, True)
        fill = colors[i % len(colors)]
        draw.text((x, y), line, font=f, fill=fill, stroke_width=2, stroke_fill=WHITE)
        y += draw.textbbox((0, 0), line, font=f)[3] + 2
    return y


def burst(draw, center, radius, fill):
    cx, cy = center
    pts = []
    for i in range(24):
        r = radius if i % 2 == 0 else radius * 0.82
        a = math.pi * 2 * i / 24 - math.pi / 2
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    draw.polygon(pts, fill=fill)


def laurel(draw, x, y, text):
    draw.text((x + 52, y), "Over", font=font(21, True), fill=INK)
    draw.text((x + 38, y + 25), text, font=font(50, True), fill=ORANGE, stroke_width=2, stroke_fill=WHITE)
    draw.text((x + 92, y + 80), "Downloads", font=font(20, True), fill=INK)
    draw.arc((x, y + 10, x + 72, y + 108), 105, 250, fill=(205, 147, 29), width=4)
    draw.arc((x + 286, y + 10, x + 358, y + 108), -70, 75, fill=(205, 147, 29), width=4)


def bubbles(draw, labels, origin):
    x, y = origin
    colors = [ORANGE, CYAN, PURPLE, GREEN, YELLOW]
    for i, label in enumerate(labels):
        w = 162 + len(label) * 4
        box = (x, y + i * 58, x + w, y + 44 + i * 58)
        pill(draw, box, label, colors[i % len(colors)], text_fill=WHITE if i != 4 else INK, width=0)


def scene(filename, bg_stops, title_lines, sub, phone_specs, labels=None, badge=None, dark=False):
    canvas = gradient((1052, 592), bg_stops).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    for cx, cy, r, col in [
        (70, 60, 105, (*ORANGE, 42)),
        (980, 90, 120, (*CYAN, 42)),
        (925, 520, 140, (*PINK, 32)),
    ]:
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    if badge:
        laurel(d, 38, 22, badge)
        text_y = 148
    else:
        text_y = 48
    headline(d, (44, text_y), title_lines, [ORANGE, INK if not dark else WHITE, BLUE], 430)
    d.text((48, text_y + 142), sub, font=font(25, True), fill=INK if not dark else WHITE)
    if labels:
        bubbles(d, labels, (50, text_y + 190))
    for spec in phone_specs:
        layer = phone(SCREENSHOTS[spec["key"]], spec["h"], spec.get("crop_bottom", 0), spec.get("rotate", 0))
        paste_phone(canvas, layer, spec["xy"], spec.get("reflection", True))
    canvas.convert("RGB").save(FINALS / filename, quality=96)


def feature_graphic():
    canvas = gradient((1024, 500), [(255, 250, 246), (249, 236, 255), (229, 248, 255)]).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    burst(d, (870, 104), 84, (255, 210, 49, 255))
    d.text((802, 74), "NEW", font=font(34, True), fill=INK)
    d.text((62, 42), "Smart", font=font(70, True), fill=ORANGE, stroke_width=2, stroke_fill=WHITE)
    d.text((62, 116), "Launcher", font=font(70, True), fill=INK)
    d.text((68, 210), "Home screen + Privacy vault + Clock", font=font(27, True), fill=(75, 76, 86))
    pill(d, (68, 284, 342, 340), "All-in-one launcher", ORANGE, text_fill=WHITE, width=0)
    specs = [
        {"key": "home", "h": 350, "xy": (394, 92), "rotate": -4},
        {"key": "library", "h": 374, "xy": (550, 68)},
        {"key": "privacy", "h": 340, "xy": (724, 106), "rotate": 4},
    ]
    for spec in specs:
        layer = phone(SCREENSHOTS[spec["key"]], spec["h"], spec.get("crop_bottom", 0), spec.get("rotate", 0))
        paste_phone(canvas, layer, spec["xy"], True)
    canvas.convert("RGB").save(FINALS / "feature-graphic-1024x500-v2.png", quality=96)


def create_assets():
    scene(
        "play-screenshot-01-all-in-one-1052x592.png",
        [(255, 252, 245), (241, 244, 255), (231, 253, 255)],
        ["One Launcher", "Does It All"],
        "Home. Search. Vault. Clock.",
        [
            {"key": "home", "h": 352, "xy": (430, 116), "rotate": -6},
            {"key": "library", "h": 394, "xy": (573, 86)},
            {"key": "privacy", "h": 352, "xy": (742, 116), "rotate": 6},
        ],
        labels=["Smart Search", "App Lock", "Vault", "Alarm"],
    )
    scene(
        "play-screenshot-02-custom-home-1052x592.png",
        [(255, 245, 234), (255, 238, 246), (235, 247, 255)],
        ["Customize", "Your Phone"],
        "Fast home screen with dock and widgets",
        [
            {"key": "home", "h": 432, "xy": (506, 66), "rotate": -4},
            {"key": "home_clean", "h": 390, "xy": (700, 88), "rotate": 4},
        ],
        labels=["Dock", "Widgets", "Pages"],
    )
    scene(
        "play-screenshot-03-app-library-1052x592.png",
        [(246, 252, 255), (236, 244, 255), (255, 248, 241)],
        ["Find Apps", "Faster"],
        "Organized app library and instant search",
        [
            {"key": "library", "h": 430, "xy": (492, 58), "rotate": -3},
            {"key": "search", "h": 396, "xy": (697, 78), "rotate": 5},
        ],
        labels=["Categories", "Search", "Shortcuts"],
    )
    scene(
        "play-screenshot-04-privacy-suite-1052x592.png",
        [(17, 21, 31), (36, 30, 54), (16, 45, 55)],
        ["Lock Apps", "Hide Files"],
        "Private tools built into your launcher",
        [
            {"key": "privacy", "h": 406, "xy": (484, 70), "rotate": -3},
            {"key": "vault", "h": 390, "xy": (704, 90), "rotate": 4, "crop_bottom": 110},
        ],
        labels=["PIN", "Pattern", "Vault"],
        dark=True,
    )
    scene(
        "play-screenshot-05-clock-tools-1052x592.png",
        [(10, 10, 12), (27, 29, 40), (42, 24, 30)],
        ["Wake", "On Time"],
        "Alarm, timer, stopwatch, world clock",
        [
            {"key": "clock", "h": 414, "xy": (482, 70), "rotate": -4},
            {"key": "timer", "h": 392, "xy": (700, 92), "rotate": 5},
        ],
        labels=["Alarm", "Timer", "Stopwatch"],
        dark=True,
    )
    scene(
        "play-screenshot-06-zero-clutter-1052x592.png",
        [(255, 252, 246), (248, 240, 255), (228, 248, 243)],
        ["Zero Clutter", "More Control"],
        "A cleaner daily Android experience",
        [
            {"key": "home_clean", "h": 398, "xy": (396, 88), "rotate": -7},
            {"key": "search", "h": 392, "xy": (590, 86)},
            {"key": "privacy", "h": 364, "xy": (770, 116), "rotate": 7},
        ],
        labels=["No chaos", "Private", "Useful"],
    )
    feature_graphic()


def notes_and_sources():
    for name, path in SCREENSHOTS.items():
        copy2(path, SOURCES / f"{name}{path.suffix.lower()}")
    (PROMPTS / "v2-style-analysis.md").write_text(
        """# V2 Style Analysis

The linked launcher listings use wide Play Store screenshot creatives, not quiet portrait posters.

Observed style:
- Landscape 16:9 canvases with white, pastel, or glossy gradient backgrounds.
- 2-5 phone screenshots per asset, often overlapping with rotations and reflections.
- Large top-left or centered headline copy with bright gradient/accent color.
- Short feature pills: Widgets, Themes, App Lock, Search, Vault, Alarm.
- High visual density for ASO scanning, with screenshots taking most of the image.

V2 response:
- Generated wide `1052x592` Play screenshot graphics plus a `1024x500` feature graphic.
- Avoided broken/setup/ad-heavy source images.
- Used clean home, app library, search, privacy settings, vault, and clock states.
""",
        encoding="utf-8",
    )
    (PROMPTS / "asset-manifest-v2.md").write_text(
        """# Smart Launcher Promotional Assets V2

Finals are in `finals/`.

- `feature-graphic-1024x500-v2.png`
- `play-screenshot-01-all-in-one-1052x592.png`
- `play-screenshot-02-custom-home-1052x592.png`
- `play-screenshot-03-app-library-1052x592.png`
- `play-screenshot-04-privacy-suite-1052x592.png`
- `play-screenshot-05-clock-tools-1052x592.png`
- `play-screenshot-06-zero-clutter-1052x592.png`
- `v2-preview-contact-sheet.jpg`

Reference pages and downloaded reference screenshots are under `references/`.
Clean source screenshots copied into `source-examples/`.
""",
        encoding="utf-8",
    )


def preview_sheet():
    files = sorted([p for p in FINALS.glob("*.png")])
    thumbs = []
    w, h = 410, 250
    for p in files:
        im = Image.open(p).convert("RGB")
        im.thumbnail((w, h - 22))
        tile = Image.new("RGB", (w, h), (235, 235, 235))
        tile.paste(im, ((w - im.width) // 2, 4))
        ImageDraw.Draw(tile).text((5, h - 17), p.name[:56], font=font(12), fill=INK)
        thumbs.append(tile)
    cols = 2
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * w, rows * h), (215, 215, 215))
    for i, tile in enumerate(thumbs):
        sheet.paste(tile, ((i % cols) * w, (i // cols) * h))
    sheet.save(FINALS / "v2-preview-contact-sheet.jpg", quality=92)


def main():
    ensure_dirs()
    create_assets()
    notes_and_sources()
    preview_sheet()


if __name__ == "__main__":
    main()
