from pathlib import Path
from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
FINALS = ROOT / "finals"
RAW_READY = FINALS / "1080x1920"
PROMO_READY = FINALS / "1052x592"
RAW_READY.mkdir(parents=True, exist_ok=True)
PROMO_READY.mkdir(parents=True, exist_ok=True)


def fit_image(src: Path, out_dir: Path, size: tuple[int, int]) -> None:
    with Image.open(src) as image:
        image = ImageOps.fit(image.convert("RGB"), size, method=Image.Resampling.LANCZOS)
        image.save(out_dir / src.name, quality=96)


def main() -> None:
    fit_image(FINALS / "01-ios-launcher-os-theme-raw.png", RAW_READY, (1080, 1920))
    fit_image(FINALS / "02-ios-launcher-os-theme-promo.png", PROMO_READY, (1052, 592))
    print("Prepared corrected iOS theme assets")


if __name__ == "__main__":
    main()
