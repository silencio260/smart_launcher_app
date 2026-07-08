from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math


ROOT = Path(__file__).resolve().parent
FINALS = ROOT / "finals"
READY = FINALS / "play-store-ready"
PROMPTS = ROOT / "prompts"


def font(size):
    for candidate in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Users/faruqshabi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/lib/python3.12/site-packages/reportlab/fonts/Vera.ttf",
    ):
        try:
            return ImageFont.truetype(candidate, size=size)
        except Exception:
            pass
    return ImageFont.load_default()


def crop_cover(im, size):
    tw, th = size
    w, h = im.size
    target = tw / th
    if w / h > target:
        nw = int(h * target)
        left = (w - nw) // 2
        im = im.crop((left, 0, left + nw, h))
    else:
        nh = int(w / target)
        top = (h - nh) // 2
        im = im.crop((0, top, w, top + nh))
    return im.resize(size, Image.Resampling.LANCZOS)


def prepare():
    READY.mkdir(parents=True, exist_ok=True)
    mapping = [
        ("ai-feature-graphic-smart-launcher.png", "feature-graphic-1024x500-ai.png", (1024, 500)),
        ("ai-play-screenshot-01-one-launcher.png", "play-screenshot-01-one-launcher-1052x592-ai.png", (1052, 592)),
        ("ai-play-screenshot-02-customize-phone.png", "play-screenshot-02-customize-phone-1052x592-ai.png", (1052, 592)),
        ("ai-play-screenshot-03-privacy-suite.png", "play-screenshot-03-privacy-suite-1052x592-ai.png", (1052, 592)),
        ("ai-play-screenshot-04-search-library.png", "play-screenshot-04-search-library-1052x592-ai.png", (1052, 592)),
        ("ai-play-screenshot-05-clock-tools.png", "play-screenshot-05-clock-tools-1052x592-ai.png", (1052, 592)),
        ("ai-play-screenshot-06-discover-feed.png", "play-screenshot-06-discover-feed-1052x592-ai.png", (1052, 592)),
    ]
    for src_name, dest_name, size in mapping:
        src = FINALS / src_name
        if not src.exists():
            continue
        im = Image.open(src).convert("RGB")
        crop_cover(im, size).save(READY / dest_name, quality=96)


def preview():
    files = sorted([p for p in READY.glob("*.png")])
    thumbs = []
    tile_w, tile_h = 430, 280
    for p in files:
        im = Image.open(p).convert("RGB")
        im.thumbnail((tile_w, tile_h - 30))
        tile = Image.new("RGB", (tile_w, tile_h), (232, 232, 232))
        tile.paste(im, ((tile_w - im.width) // 2, 6))
        ImageDraw.Draw(tile).text((6, tile_h - 22), p.name[:58], fill=(20, 20, 20), font=font(13))
        thumbs.append(tile)
    cols = 2
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * tile_w, rows * tile_h), (212, 212, 212))
    for i, tile in enumerate(thumbs):
        sheet.paste(tile, ((i % cols) * tile_w, (i // cols) * tile_h))
    sheet.save(FINALS / "v3-ai-generated-preview-contact-sheet.jpg", quality=92)


def notes():
    PROMPTS.mkdir(parents=True, exist_ok=True)
    (PROMPTS / "v3-generation-notes.md").write_text(
        """# V3 AI-Generated Promotional Assets

This version uses the provided screenshots only as inspiration. The final images are generated with the internal image generation tool and do not paste the supplied app screenshots into the promotional art.

Direction:
- Inspired by the linked Play Store launcher listings.
- Wide ASO screenshots with bold headlines, overlapping phones, bright accents, glossy reflections, and feature pills.
- Generated fictional Smart Launcher UI for home, app library/search, privacy vault/app lock, clock, and Discover feed.
- Avoids the buggy/incomplete supplied screenshots as final image content.

Outputs:
- Original AI generations: `finals/ai-*.png`
- Store-ready crops: `finals/play-store-ready/`
- Contact sheet: `finals/v3-ai-generated-preview-contact-sheet.jpg`
""",
        encoding="utf-8",
    )


if __name__ == "__main__":
    prepare()
    preview()
    notes()
