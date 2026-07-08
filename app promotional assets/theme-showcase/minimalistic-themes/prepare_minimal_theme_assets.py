from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
FINALS = ROOT / "finals"
RAW_READY = FINALS / "1080x1920"
PROMO_READY = FINALS / "1052x592"
RAW_READY.mkdir(parents=True, exist_ok=True)
PROMO_READY.mkdir(parents=True, exist_ok=True)

THUMB_SIZE = (216, 384)
PADDING = 24
LABEL_H = 34
BG = (242, 244, 247)
TEXT = (20, 24, 31)


def load_font(size: int):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def fit_image(src: Path, out_dir: Path, size: tuple[int, int]) -> None:
    with Image.open(src) as image:
        image = ImageOps.fit(image.convert("RGB"), size, method=Image.Resampling.LANCZOS)
        image.save(out_dir / src.name, quality=96)


def create_preview(raw_files: list[Path]) -> Path:
    cols = len(raw_files)
    width = cols * THUMB_SIZE[0] + (cols + 1) * PADDING
    height = THUMB_SIZE[1] + LABEL_H + (2 * PADDING)
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    font = load_font(16)

    for i, src in enumerate(raw_files):
        x = PADDING + i * (THUMB_SIZE[0] + PADDING)
        y = PADDING
        with Image.open(src) as image:
            thumb = ImageOps.fit(image.convert("RGB"), THUMB_SIZE, method=Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x, y))
        label = src.stem.replace("-", " ").title()
        draw.text((x, y + THUMB_SIZE[1] + 8), label, fill=TEXT, font=font)

    out = FINALS / "minimalistic-themes-preview-contact-sheet.jpg"
    sheet.save(out, quality=92)
    return out


def main() -> None:
    raw_files = sorted(
        path
        for path in FINALS.glob("*.png")
        if path.name[:2].isdigit() and path.name.endswith("-minimal-theme.png")
    )
    for src in raw_files:
        fit_image(src, RAW_READY, (1080, 1920))

    fit_image(FINALS / "06-minimal-themes-promo.png", PROMO_READY, (1052, 592))
    create_preview([RAW_READY / src.name for src in raw_files])
    print(f"Prepared {len(raw_files)} minimal raw themes and 1 promo")


if __name__ == "__main__":
    main()
