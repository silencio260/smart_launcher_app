from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
FINALS = ROOT / "finals"
READY = FINALS / "play-store-ready"
READY.mkdir(parents=True, exist_ok=True)

TARGET_SIZE = (1052, 592)
THUMB_SIZE = (526, 296)
PADDING = 28
LABEL_H = 38
BG = (246, 247, 249)
TEXT = (22, 27, 34)


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


def resize_store_ready(src: Path) -> Path:
    out = READY / src.name
    with Image.open(src) as image:
        image = image.convert("RGB")
        image = ImageOps.fit(image, TARGET_SIZE, method=Image.Resampling.LANCZOS)
        image.save(out, quality=96)
    return out


def create_contact_sheet(files: list[Path]) -> Path:
    cols = 3
    rows = (len(files) + cols - 1) // cols
    width = cols * THUMB_SIZE[0] + (cols + 1) * PADDING
    height = rows * (THUMB_SIZE[1] + LABEL_H) + (rows + 1) * PADDING
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    font = load_font(20)

    for i, src in enumerate(files):
        row, col = divmod(i, cols)
        x = PADDING + col * (THUMB_SIZE[0] + PADDING)
        y = PADDING + row * (THUMB_SIZE[1] + LABEL_H + PADDING)
        with Image.open(src) as image:
            thumb = ImageOps.fit(image.convert("RGB"), THUMB_SIZE, method=Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x, y))
        label = src.stem.replace("-", " ").title()
        draw.text((x, y + THUMB_SIZE[1] + 8), label, fill=TEXT, font=font)

    out = FINALS / "individual-promo-mockups-preview-contact-sheet.jpg"
    sheet.save(out, quality=92)
    return out


def main():
    files = sorted(
        path
        for path in FINALS.glob("*.png")
        if path.name[:2].isdigit() and path.name.endswith("-promo.png")
    )
    for src in files:
        resize_store_ready(src)
    create_contact_sheet(files)
    print(f"Processed {len(files)} promo mockups")


if __name__ == "__main__":
    main()
