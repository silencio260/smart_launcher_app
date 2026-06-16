from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math


ROOT = Path(__file__).resolve().parent
FINALS = ROOT / "finals"
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


def build_preview():
    files = sorted([p for p in FINALS.glob("*.png") if p.name != "individual-mockups-preview-contact-sheet.png"])
    tile_w, tile_h = 320, 430
    thumbs = []
    for p in files:
        im = Image.open(p).convert("RGB")
        im.thumbnail((tile_w, tile_h - 34))
        tile = Image.new("RGB", (tile_w, tile_h), (235, 235, 235))
        tile.paste(im, ((tile_w - im.width) // 2, 6))
        ImageDraw.Draw(tile).text((8, tile_h - 25), p.name[:42], font=font(13), fill=(24, 24, 24))
        thumbs.append(tile)
    cols = 3
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * tile_w, rows * tile_h), (214, 214, 214))
    for i, tile in enumerate(thumbs):
        sheet.paste(tile, ((i % cols) * tile_w, (i // cols) * tile_h))
    sheet.save(FINALS / "individual-mockups-preview-contact-sheet.jpg", quality=92)


def write_manifest():
    PROMPTS.mkdir(parents=True, exist_ok=True)
    (PROMPTS / "individual-mockups-manifest.md").write_text(
        """# Individual AI Mockups

These assets are generated with the internal image generation tool. They do not paste or reuse the provided screenshots; those screenshots and the Play Store links were used only as visual/product inspiration.

## Finals

- `01-launcher-home-mockup.png`
- `02-app-library-mockup.png`
- `03-smart-search-mockup.png`
- `04-discover-feed-mockup.png`
- `05-privacy-hub-mockup.png`
- `06-app-lock-mockup.png`
- `07-app-hider-mockup.png`
- `08-vault-mockup.png`
- `09-clock-mockup.png`
- `individual-mockups-preview-contact-sheet.jpg`

## Intended Use

Use these as standalone feature mockups or source pieces for Play Store screenshots, feature graphics, ads, and social creatives.
""",
        encoding="utf-8",
    )


if __name__ == "__main__":
    build_preview()
    write_manifest()
