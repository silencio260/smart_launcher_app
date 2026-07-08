from pathlib import Path
from shutil import copy2
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app promotional assets"
FINALS = OUT / "finals"
RAW = FINALS / "raw-screenshots"
SOURCES = OUT / "source-examples"
PROMPTS = OUT / "prompts"

ORANGE = (255, 103, 31)
CHARCOAL = (17, 18, 22)
INK = (22, 24, 29)
WHITE = (250, 250, 247)
MUTED = (226, 226, 220)
TEAL = (0, 180, 174)
BLUE = (52, 106, 255)

SCREENSHOTS = {
    "home": ROOT / "templates/App Screenshots/launcher_discover_search_library/photo_2026-06-02 9.33.25 PM.jpeg",
    "search": ROOT / "templates/App Screenshots/launcher_discover_search_library/photo_2026-06-02 9.46.10 PM.jpeg",
    "library": ROOT / "templates/App Screenshots/photo_2026-05-03 11.53.45 PM.jpeg",
    "privacy": ROOT / "templates/App Screenshots/sub apps/app lock/photo_2026-06-02 10.07.16 AM.jpeg",
    "clock": ROOT / "templates/App Screenshots/sub apps/alarm/alarm 2/photo_2026-06-01 11.55.35 PM.jpeg",
    "timer": ROOT / "templates/App Screenshots/sub apps/alarm/alarm 2/photo_2026-06-01 11.55.57 PM.jpeg",
}


def ensure_dirs():
    for folder in (FINALS, RAW, SOURCES, PROMPTS):
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


def gradient(size, colors):
    w, h = size
    img = Image.new("RGB", size)
    pix = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        if t < 0.5:
            a, b = colors[0], colors[1]
            tt = t * 2
        else:
            a, b = colors[1], colors[2]
            tt = (t - 0.5) * 2
        col = tuple(int(a[i] * (1 - tt) + b[i] * tt) for i in range(3))
        for x in range(w):
            pix[x, y] = col
    return img


def crop_cover(im, size):
    tw, th = size
    ratio = tw / th
    w, h = im.size
    if w / h > ratio:
        nw = int(h * ratio)
        left = (w - nw) // 2
        im = im.crop((left, 0, left + nw, h))
    else:
        nh = int(w / ratio)
        top = max(0, (h - nh) // 2)
        im = im.crop((0, top, w, top + nh))
    return im.resize(size, Image.Resampling.LANCZOS)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width, im.height), radius=radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im.convert("RGBA"), (0, 0), mask)
    return out


def paste_shadow(base, layer, xy, blur=28, offset=(0, 18), alpha=90):
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    mask = layer.getchannel("A")
    shadow.putalpha(mask.point(lambda p: int(p * alpha / 255)))
    shadow = Image.alpha_composite(Image.new("RGBA", shadow.size, (0, 0, 0, 0)), shadow)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow, (xy[0] + offset[0], xy[1] + offset[1]))
    base.alpha_composite(layer, xy)


def phone(path, width, crop=None):
    im = Image.open(path).convert("RGB")
    if crop:
        im = im.crop(crop)
    h = int(width * im.height / im.width)
    im = im.resize((width, h), Image.Resampling.LANCZOS)
    frame_pad = max(8, width // 34)
    radius = max(28, width // 12)
    frame = Image.new("RGBA", (width + frame_pad * 2, h + frame_pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, frame.width, frame.height), radius=radius + frame_pad, fill=(8, 9, 12, 255))
    frame.alpha_composite(rounded(im, radius), (frame_pad, frame_pad))
    return frame


def wrap_text(text, draw, fnt, max_width):
    words = text.split()
    lines = []
    line = ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textbbox((0, 0), trial, font=fnt)[2] <= max_width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def draw_wrapped(draw, xy, text, fnt, fill, max_width, line_gap=10):
    x, y = xy
    for line in wrap_text(text, draw, fnt, max_width):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += draw.textbbox((0, 0), line, font=fnt)[3] + line_gap
    return y


def pill(draw, box, label, fill, text_fill, fnt):
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=fill)
    bbox = draw.textbbox((0, 0), label, font=fnt)
    x = box[0] + (box[2] - box[0] - (bbox[2] - bbox[0])) // 2
    y = box[1] + (box[3] - box[1] - (bbox[3] - bbox[1])) // 2 - 2
    draw.text((x, y), label, font=fnt, fill=text_fill)


def promotional_screenshot(filename, title, subtitle, shot_key, badge_label, accent=ORANGE, dark=False):
    bg = gradient((1080, 1920), [(255, 248, 239), (246, 247, 246), (225, 243, 242)])
    if dark:
        bg = gradient((1080, 1920), [(8, 8, 9), (22, 22, 24), (6, 12, 16)])
    canvas = bg.convert("RGBA")
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((64, 62, 216, 74), radius=6, fill=accent)
    d.text((64, 112), "Smart Launcher", font=font(32, True), fill=WHITE if dark else INK)
    d.text((64, 174), title, font=font(72, True), fill=WHITE if dark else INK)
    draw_wrapped(d, (68, 344), subtitle, font(31), MUTED if dark else (82, 84, 88), 920, 12)
    pill(d, (68, 508, 430, 574), badge_label, accent, WHITE, font(26, True))
    p = phone(SCREENSHOTS[shot_key], 580)
    x = (1080 - p.width) // 2
    y = 618
    paste_shadow(canvas, p, (x, y), blur=34, offset=(0, 18), alpha=95)
    canvas.convert("RGB").save(FINALS / filename, quality=96)


def feature_graphic():
    canvas = gradient((1024, 500), [(12, 14, 18), (35, 31, 29), (72, 39, 24)]).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    d.ellipse((-130, -120, 220, 230), fill=(255, 103, 31, 70))
    d.ellipse((750, 310, 1100, 660), fill=(0, 180, 174, 52))
    d.rounded_rectangle((62, 66, 194, 78), radius=6, fill=ORANGE)
    d.text((62, 106), "Smart Launcher", font=font(48, True), fill=WHITE)
    draw_wrapped(d, (64, 178), "One launcher. Zero clutter. Total privacy.", font(34, True), (246, 246, 240), 390, 8)
    d.text((66, 320), "Home screen, vault, and clock in one app.", font=font(22), fill=(218, 218, 208))
    pill(d, (64, 380, 282, 432), "GENREVIBES", ORANGE, WHITE, font(19, True))
    shots = [
        (SCREENSHOTS["home"], 232, 426, 28),
        (SCREENSHOTS["privacy"], 205, 590, 82),
        (SCREENSHOTS["clock"], 220, 744, 44),
    ]
    for path, w, x, y in shots:
        p = phone(path, w)
        paste_shadow(canvas, p, (x, y), blur=24, offset=(0, 14), alpha=80)
    canvas.convert("RGB").save(FINALS / "google-play-feature-graphic-1024x500.png", quality=96)


def social_square():
    canvas = gradient((1080, 1080), [(255, 250, 244), (245, 247, 247), (229, 247, 244)]).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((70, 72, 224, 86), radius=7, fill=ORANGE)
    d.text((70, 124), "Your phone,", font=font(76, True), fill=INK)
    d.text((70, 214), "finally yours.", font=font(76, True), fill=INK)
    d.text((74, 330), "Launcher + privacy suite + clock", font=font(34), fill=(76, 78, 84))
    paste_shadow(canvas, phone(SCREENSHOTS["home"], 375), (98, 444), blur=30, offset=(0, 18), alpha=85)
    paste_shadow(canvas, phone(SCREENSHOTS["privacy"], 340), (512, 386), blur=30, offset=(0, 18), alpha=85)
    pill(d, (72, 956, 426, 1022), "Zero clutter", ORANGE, WHITE, font(28, True))
    pill(d, (456, 956, 846, 1022), "Total privacy", CHARCOAL, WHITE, font(28, True))
    canvas.convert("RGB").save(FINALS / "social-square-1080x1080.png", quality=96)


def social_story():
    canvas = gradient((1080, 1920), [(10, 12, 15), (27, 23, 23), (58, 30, 20)]).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((72, 92, 238, 106), radius=7, fill=ORANGE)
    d.text((72, 148), "Search less.", font=font(82, True), fill=WHITE)
    d.text((72, 246), "Hide more.", font=font(82, True), fill=WHITE)
    draw_wrapped(d, (76, 370), "A calmer Android launcher with built-in app lock, app hider, vault, RSS discover, and alarm clock.", font(34), (226, 224, 218), 900, 14)
    paste_shadow(canvas, phone(SCREENSHOTS["search"], 540), (278, 650), blur=34, offset=(0, 18), alpha=95)
    pill(d, (210, 1750, 870, 1840), "One install. More control.", ORANGE, WHITE, font(34, True))
    canvas.convert("RGB").save(FINALS / "social-story-1080x1920.png", quality=96)


def raw_screenshots():
    for name, path in SCREENSHOTS.items():
        im = Image.open(path).convert("RGB")
        im = crop_cover(im, (1080, 1920))
        im.save(RAW / f"raw-{name}-1080x1920.jpg", quality=95)
        copy2(path, SOURCES / f"{name}{path.suffix.lower()}")


def notes():
    (PROMPTS / "google-ai-stitch-prompt.md").write_text(
        """# Google AI Stitch Prompt

Design promotional screens for Smart Launcher, an Android home-replacement app by GENREVIBES TECHNOLOGIES INC with a built-in privacy vault, app lock, app hider, RSS discover feed, smart search, and alarm-first clock.

Primary accent: warm GenRevibes orange. Privacy and clock screens should feel monochrome black and white, calm, premium, and vault-like. Use real app UI as the source of truth. Show a customizable home screen with dock and smart search pill, an app library, smart search results, app lock/privacy settings, and a monochrome clock/timer screen.

Tone: clean, premium, trustworthy, edge-to-edge minimal UI. Avoid fake features, fake device hands, heavy shadows, busy gradients, and misleading claims.

Preferred copy options:
- Your phone, finally yours.
- One launcher. Zero clutter. Total privacy.
- Home screen, vault, and clock in one app.
- Search less. Hide more. Wake on time.
""",
        encoding="utf-8",
    )
    (PROMPTS / "asset-manifest.md").write_text(
        """# Smart Launcher Promotional Assets

Generated from the supplied brief and local screenshot folder.

## Finals

- `finals/google-play-feature-graphic-1024x500.png` — Google Play feature graphic.
- `finals/promo-screenshot-01-home-1080x1920.png` — home screen customization promo.
- `finals/promo-screenshot-02-search-1080x1920.png` — smart search promo.
- `finals/promo-screenshot-03-privacy-1080x1920.png` — privacy suite promo.
- `finals/promo-screenshot-04-clock-1080x1920.png` — alarm/clock promo.
- `finals/promo-screenshot-05-library-1080x1920.png` — app library promo.
- `finals/social-square-1080x1080.png` — square social creative.
- `finals/social-story-1080x1920.png` — story/reel creative.
- `finals/raw-screenshots/` — 1080x1920 raw crops from selected screenshots.

## Notes

The promotional screenshots use real supplied screenshots and do not implement assets into the app. Source screenshots are copied into `source-examples/`.
""",
        encoding="utf-8",
    )


def main():
    ensure_dirs()
    raw_screenshots()
    feature_graphic()
    promotional_screenshot(
        "promo-screenshot-01-home-1080x1920.png",
        "Your phone, finally yours.",
        "A calmer Android home screen with fast dock access and Smart Search always one tap away.",
        "home",
        "Custom home",
        ORANGE,
        False,
    )
    promotional_screenshot(
        "promo-screenshot-02-search-1080x1920.png",
        "Search less.",
        "Find apps, shortcuts, recent items, and the web from one clean search surface.",
        "search",
        "Smart Search",
        TEAL,
        False,
    )
    promotional_screenshot(
        "promo-screenshot-03-privacy-1080x1920.png",
        "Hide more.",
        "Built-in app lock, hider, and vault controls designed for private daily use.",
        "privacy",
        "Privacy suite",
        ORANGE,
        True,
    )
    promotional_screenshot(
        "promo-screenshot-04-clock-1080x1920.png",
        "Wake on time.",
        "Alarm, timer, stopwatch, and world clock in a quiet monochrome mini app.",
        "clock",
        "Alarm-first clock",
        BLUE,
        True,
    )
    promotional_screenshot(
        "promo-screenshot-05-library-1080x1920.png",
        "Everything organized.",
        "A searchable app library keeps the home screen clean without slowing you down.",
        "library",
        "App Library",
        ORANGE,
        False,
    )
    social_square()
    social_story()
    notes()


if __name__ == "__main__":
    main()
