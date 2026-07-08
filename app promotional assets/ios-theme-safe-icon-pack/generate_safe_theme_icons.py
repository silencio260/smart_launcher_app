from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
FINALS = ROOT / "finals"
SHEETS = ROOT / "contact-sheets"
SOURCE = Path("assets/ios_theme")
SIZE = 120
SCALE = 4
W = H = SIZE * SCALE


ICONS = [
    ("AppStoreIcon.png", "apps", ("#2355ff", "#39dbff", "#f9fbff")),
    ("BooksIcon.png", "books", ("#ff8a22", "#ffcf5c", "#fff7d8")),
    ("CalendarIcon.png", "calendar", ("#f7f8fb", "#e7edf7", "#ff5b5b")),
    ("CameraIcon.png", "camera", ("#e9eef5", "#9aa8b8", "#151922")),
    ("ClockIcon.png", "clock", ("#f7f9fd", "#cfd8e5", "#161a22")),
    ("FacetimeIcon.png", "video", ("#10c76f", "#6df2b6", "#f5fff9")),
    ("HealthIcon.png", "health", ("#fff5f7", "#ffe4eb", "#f53e6b")),
    ("ItunesIcon.png", "store_music", ("#b950ff", "#ff59b8", "#ffffff")),
    ("MailIcon.png", "mail", ("#1a8cff", "#6ce0ff", "#ffffff")),
    ("MapsIcon.png", "maps", ("#67dc7a", "#4aa7ff", "#ffffff")),
    ("MessagesIcon.png", "messages", ("#0fcf73", "#8df7a8", "#ffffff")),
    ("MusicIcon.png", "music", ("#ff2f6d", "#ff7a3d", "#ffffff")),
    ("NewsIcon.png", "news", ("#ff384f", "#b60e24", "#ffffff")),
    ("NotesIcon.png", "notes", ("#fff9d8", "#ffe76b", "#222831")),
    ("PhotosIcon.png", "photos", ("#f8fbff", "#e8eef7", "#ff4f70")),
    ("RemindersIcon.png", "reminders", ("#f8fbff", "#dfe7f2", "#3087ff")),
    ("SafariIcon.png", "browser", ("#1da9ff", "#69f2ff", "#ffffff")),
    ("SettingsIcon.png", "settings", ("#8c99a8", "#d8e0ea", "#ffffff")),
    ("StocksIcon.png", "stocks", ("#101722", "#263242", "#58d68d")),
    ("VideosIcon.png", "video", ("#282d3c", "#666f86", "#ffffff")),
    ("WalletIcon.png", "wallet", ("#202530", "#4d5968", "#f7f9fc")),
    ("WeatherIcon.png", "weather", ("#138aff", "#65d8ff", "#ffffff")),
]


def sc(v: float) -> int:
    return int(round(v * SCALE))


def rgb(hex_color: str) -> tuple[int, int, int]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def rounded_mask() -> Image.Image:
    mask = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=sc(27), fill=255)
    return mask


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def background(top: str, bottom: str, accent: str, seed: int) -> Image.Image:
    random.seed(seed)
    top_rgb, bottom_rgb, accent_rgb = rgb(top), rgb(bottom), rgb(accent)
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        for x in range(W):
            side = .08 * math.sin((x / W) * math.pi)
            px[x, y] = lerp(top_rgb, bottom_rgb, min(1, max(0, t + side)))

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([sc(-20), sc(-24), sc(96), sc(88)], fill=(*accent_rgb, 58))
    gd.ellipse([sc(52), sc(62), sc(148), sc(146)], fill=(*top_rgb, 42))
    glow = glow.filter(ImageFilter.GaussianBlur(sc(18)))
    img = Image.alpha_composite(img.convert("RGBA"), glow)

    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    sd.rounded_rectangle([sc(3), sc(3), sc(117), sc(117)], radius=sc(24), outline=(255, 255, 255, 70), width=sc(1.2))
    sd.arc([sc(-25), sc(-25), sc(145), sc(145)], 202, 336, fill=(255, 255, 255, 32), width=sc(5))
    return Image.alpha_composite(img, shade)


def icon_base(palette: tuple[str, str, str], seed: int) -> Image.Image:
    img = background(*palette, seed)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(img, (0, 0), rounded_mask())
    return out


def shadow(draw: ImageDraw.ImageDraw, box, radius: int, alpha=65):
    x0, y0, x1, y1 = box
    draw.rounded_rectangle([x0 + sc(2), y0 + sc(4), x1 + sc(2), y1 + sc(4)], radius=radius, fill=(0, 0, 0, alpha))


def draw_camera(d: ImageDraw.ImageDraw):
    shadow(d, [sc(22), sc(36), sc(98), sc(86)], sc(16))
    d.rounded_rectangle([sc(22), sc(36), sc(98), sc(86)], radius=sc(16), fill=(245, 248, 252, 238))
    d.rounded_rectangle([sc(36), sc(28), sc(62), sc(42)], radius=sc(7), fill=(245, 248, 252, 238))
    d.ellipse([sc(43), sc(39), sc(83), sc(79)], fill=(28, 33, 42, 245))
    d.ellipse([sc(52), sc(48), sc(74), sc(70)], fill=(82, 101, 122, 255))
    d.ellipse([sc(57), sc(53), sc(69), sc(65)], fill=(11, 15, 21, 255))
    d.ellipse([sc(77), sc(43), sc(85), sc(51)], fill=(81, 202, 255, 240))


def draw_weather(d: ImageDraw.ImageDraw):
    d.ellipse([sc(22), sc(22), sc(62), sc(62)], fill=(255, 221, 74, 255))
    for ang in range(0, 360, 45):
        cx, cy = sc(42), sc(42)
        r1, r2 = sc(28), sc(38)
        d.line([cx + math.cos(math.radians(ang)) * r1, cy + math.sin(math.radians(ang)) * r1, cx + math.cos(math.radians(ang)) * r2, cy + math.sin(math.radians(ang)) * r2], fill=(255, 226, 92, 210), width=sc(3))
    d.ellipse([sc(32), sc(57), sc(70), sc(91)], fill=(255, 255, 255, 246))
    d.ellipse([sc(55), sc(48), sc(91), sc(91)], fill=(255, 255, 255, 246))
    d.rounded_rectangle([sc(29), sc(69), sc(98), sc(92)], radius=sc(12), fill=(255, 255, 255, 246))


def draw_mail(d: ImageDraw.ImageDraw):
    shadow(d, [sc(20), sc(34), sc(100), sc(86)], sc(13))
    d.rounded_rectangle([sc(20), sc(34), sc(100), sc(86)], radius=sc(13), fill=(255, 255, 255, 246))
    d.line([sc(25), sc(42), sc(60), sc(66), sc(95), sc(42)], fill=(38, 139, 236, 230), width=sc(5))
    d.line([sc(25), sc(80), sc(50), sc(59)], fill=(38, 139, 236, 120), width=sc(3))
    d.line([sc(95), sc(80), sc(70), sc(59)], fill=(38, 139, 236, 120), width=sc(3))


def draw_messages(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(22), sc(31), sc(98), sc(78)], radius=sc(23), fill=(255, 255, 255, 248))
    d.polygon([(sc(50), sc(77)), (sc(43), sc(96)), (sc(67), sc(78))], fill=(255, 255, 255, 248))
    for x in (43, 60, 77):
        d.ellipse([sc(x - 4), sc(51), sc(x + 4), sc(59)], fill=(36, 180, 100, 180))


def draw_music(d: ImageDraw.ImageDraw, double=False):
    color = (255, 255, 255, 250)
    d.ellipse([sc(27), sc(68), sc(52), sc(94)], fill=color)
    d.rectangle([sc(48), sc(27), sc(57), sc(80)], fill=color)
    d.line([sc(53), sc(28), sc(88), sc(21)], fill=color, width=sc(9))
    if double:
        d.ellipse([sc(69), sc(61), sc(94), sc(87)], fill=color)
        d.rectangle([sc(86), sc(20), sc(95), sc(72)], fill=color)
        d.line([sc(54), sc(28), sc(91), sc(21)], fill=color, width=sc(9))


def draw_video(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(22), sc(36), sc(75), sc(83)], radius=sc(13), fill=(255, 255, 255, 246))
    d.polygon([(sc(75), sc(50)), (sc(101), sc(36)), (sc(101), sc(83)), (sc(75), sc(69))], fill=(255, 255, 255, 246))


def draw_calendar(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(18), sc(19), sc(102), sc(101)], radius=sc(14), fill=(255, 255, 255, 248))
    d.rounded_rectangle([sc(18), sc(19), sc(102), sc(43)], radius=sc(14), fill=(255, 80, 80, 250))
    d.rectangle([sc(18), sc(34), sc(102), sc(48)], fill=(255, 80, 80, 250))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", sc(36))
    except OSError:
        font = ImageFont.load_default(size=sc(34))
    d.text((sc(44), sc(52)), "7", fill=(35, 40, 50, 245), font=font)


def draw_clock(d: ImageDraw.ImageDraw):
    d.ellipse([sc(19), sc(19), sc(101), sc(101)], fill=(255, 255, 255, 248), outline=(24, 27, 35, 235), width=sc(3))
    for ang in range(0, 360, 30):
        cx, cy = sc(60), sc(60)
        r1, r2 = sc(34), sc(39)
        d.line([cx + math.cos(math.radians(ang)) * r1, cy + math.sin(math.radians(ang)) * r1, cx + math.cos(math.radians(ang)) * r2, cy + math.sin(math.radians(ang)) * r2], fill=(24, 27, 35, 190), width=sc(1))
    d.line([sc(60), sc(60), sc(60), sc(34)], fill=(24, 27, 35, 255), width=sc(4))
    d.line([sc(60), sc(60), sc(80), sc(68)], fill=(24, 27, 35, 255), width=sc(4))
    d.ellipse([sc(55), sc(55), sc(65), sc(65)], fill=(24, 27, 35, 255))


def draw_settings(d: ImageDraw.ImageDraw):
    cx, cy = sc(60), sc(60)
    for i in range(12):
        ang = math.tau * i / 12
        x = cx + math.cos(ang) * sc(25)
        y = cy + math.sin(ang) * sc(25)
        d.rounded_rectangle([x - sc(5), y - sc(12), x + sc(5), y + sc(12)], radius=sc(4), fill=(255, 255, 255, 235))
    d.ellipse([sc(30), sc(30), sc(90), sc(90)], fill=(245, 248, 252, 238))
    d.ellipse([sc(43), sc(43), sc(77), sc(77)], fill=(122, 136, 152, 255))
    d.ellipse([sc(52), sc(52), sc(68), sc(68)], fill=(235, 241, 248, 255))


def draw_photos(d: ImageDraw.ImageDraw):
    cx, cy = sc(60), sc(60)
    colors = ["#ff4f70", "#ff9f3d", "#ffd447", "#37d67a", "#35c5ff", "#6f7cff", "#b65cff", "#ff6ec7"]
    for i, color in enumerate(colors):
        ang = math.tau * i / len(colors)
        px = cx + math.cos(ang) * sc(22)
        py = cy + math.sin(ang) * sc(22)
        d.ellipse([px - sc(15), py - sc(20), px + sc(15), py + sc(20)], fill=(*rgb(color), 218))
    d.ellipse([sc(51), sc(51), sc(69), sc(69)], fill=(255, 255, 255, 245))


def draw_notes(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(21), sc(18), sc(99), sc(102)], radius=sc(12), fill=(255, 255, 255, 248))
    d.rectangle([sc(21), sc(18), sc(99), sc(42)], fill=(255, 225, 86, 255))
    for y in (55, 68, 81):
        d.line([sc(33), sc(y), sc(87), sc(y)], fill=(45, 50, 58, 130), width=sc(3))


def draw_reminders(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(22), sc(18), sc(98), sc(102)], radius=sc(13), fill=(255, 255, 255, 248))
    colors = [(48, 135, 255, 255), (255, 184, 54, 255), (255, 82, 106, 255), (55, 202, 120, 255)]
    for i, y in enumerate((36, 52, 68, 84)):
        d.ellipse([sc(32), sc(y - 4), sc(40), sc(y + 4)], fill=colors[i])
        d.line([sc(48), sc(y), sc(88), sc(y)], fill=(50, 58, 70, 120), width=sc(3))


def draw_browser(d: ImageDraw.ImageDraw):
    d.ellipse([sc(20), sc(20), sc(100), sc(100)], fill=(255, 255, 255, 242))
    d.ellipse([sc(29), sc(29), sc(91), sc(91)], fill=(32, 170, 244, 255))
    for x in (43, 60, 77):
        d.arc([sc(x - 18), sc(30), sc(x + 18), sc(90)], 82, 278, fill=(255, 255, 255, 92), width=sc(2))
    d.arc([sc(29), sc(42), sc(91), sc(78)], 0, 360, fill=(255, 255, 255, 110), width=sc(2))
    d.polygon([(sc(72), sc(33)), (sc(63), sc(67)), (sc(45), sc(87)), (sc(54), sc(53))], fill=(255, 255, 255, 245))
    d.polygon([(sc(72), sc(33)), (sc(54), sc(53)), (sc(62), sc(58))], fill=(255, 96, 106, 245))


def draw_maps(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(22), sc(18), sc(98), sc(102)], radius=sc(14), fill=(255, 255, 255, 248))
    d.polygon([(sc(22), sc(83)), (sc(56), sc(49)), (sc(98), sc(63)), (sc(98), sc(102)), (sc(22), sc(102))], fill=(90, 196, 104, 255))
    d.polygon([(sc(22), sc(45)), (sc(56), sc(49)), (sc(98), sc(25)), (sc(98), sc(65)), (sc(56), sc(49)), (sc(22), sc(84))], fill=(81, 164, 246, 220))
    d.line([sc(56), sc(18), sc(56), sc(102)], fill=(255, 225, 84, 245), width=sc(6))
    d.ellipse([sc(47), sc(32), sc(73), sc(58)], fill=(255, 77, 94, 255))
    d.ellipse([sc(55), sc(40), sc(65), sc(50)], fill=(255, 255, 255, 240))


def draw_health(d: ImageDraw.ImageDraw):
    d.ellipse([sc(26), sc(28), sc(61), sc(65)], fill=(245, 53, 94, 255))
    d.ellipse([sc(59), sc(28), sc(94), sc(65)], fill=(245, 53, 94, 255))
    d.polygon([(sc(27), sc(50)), (sc(93), sc(50)), (sc(60), sc(94))], fill=(245, 53, 94, 255))


def draw_books(d: ImageDraw.ImageDraw):
    for i, color in enumerate(("#ffffff", "#ffe79d", "#ff5c45")):
        x = sc(26 + i * 21)
        d.rounded_rectangle([x, sc(23), x + sc(19), sc(93)], radius=sc(5), fill=(*rgb(color), 245))
        d.line([x + sc(4), sc(32), x + sc(15), sc(32)], fill=(135, 85, 36, 120), width=sc(2))


def draw_stocks(d: ImageDraw.ImageDraw):
    for y in (34, 52, 70, 88):
        d.line([sc(20), sc(y), sc(100), sc(y)], fill=(255, 255, 255, 34), width=sc(1))
    points = [(22, 78), (38, 62), (52, 69), (67, 43), (82, 50), (99, 30)]
    d.line([(sc(x), sc(y)) for x, y in points], fill=(89, 214, 141, 255), width=sc(6), joint="curve")
    for x, y in points:
        d.ellipse([sc(x - 3), sc(y - 3), sc(x + 3), sc(y + 3)], fill=(255, 255, 255, 230))


def draw_news(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(22), sc(18), sc(98), sc(102)], radius=sc(10), fill=(255, 255, 255, 246))
    d.rectangle([sc(22), sc(18), sc(98), sc(43)], fill=(200, 24, 42, 255))
    d.rectangle([sc(32), sc(55), sc(58), sc(84)], fill=(200, 24, 42, 235))
    for y in (56, 66, 76, 86):
        d.line([sc(65), sc(y), sc(88), sc(y)], fill=(35, 40, 50, 125), width=sc(3))


def draw_wallet(d: ImageDraw.ImageDraw):
    d.rounded_rectangle([sc(20), sc(31), sc(100), sc(91)], radius=sc(13), fill=(245, 248, 252, 246))
    for i, color in enumerate(("#ff6d5a", "#ffd15c", "#4d9bff")):
        d.rounded_rectangle([sc(26), sc(25 + i * 13), sc(94), sc(48 + i * 13)], radius=sc(8), fill=(*rgb(color), 245))
    d.rounded_rectangle([sc(20), sc(54), sc(100), sc(91)], radius=sc(13), fill=(245, 248, 252, 246))


def draw_apps(d: ImageDraw.ImageDraw):
    for row in range(2):
        for col in range(2):
            x = sc(37 + col * 30)
            y = sc(35 + row * 30)
            d.rounded_rectangle([x, y, x + sc(18), y + sc(18)], radius=sc(6), fill=(255, 255, 255, 246))
    d.line([sc(60), sc(25), sc(60), sc(95)], fill=(255, 255, 255, 120), width=sc(4))
    d.line([sc(25), sc(60), sc(95), sc(60)], fill=(255, 255, 255, 120), width=sc(4))
    d.ellipse([sc(54), sc(54), sc(66), sc(66)], fill=(255, 255, 255, 248))


def draw_icon(kind: str, palette: tuple[str, str, str], seed: int) -> Image.Image:
    img = icon_base(palette, seed)
    d = ImageDraw.Draw(img, "RGBA")
    {
        "apps": draw_apps,
        "books": draw_books,
        "calendar": draw_calendar,
        "camera": draw_camera,
        "clock": draw_clock,
        "video": draw_video,
        "health": draw_health,
        "mail": draw_mail,
        "maps": draw_maps,
        "messages": draw_messages,
        "music": lambda draw: draw_music(draw, False),
        "store_music": lambda draw: draw_music(draw, True),
        "news": draw_news,
        "notes": draw_notes,
        "photos": draw_photos,
        "reminders": draw_reminders,
        "browser": draw_browser,
        "settings": draw_settings,
        "stocks": draw_stocks,
        "wallet": draw_wallet,
        "weather": draw_weather,
    }[kind](d)
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def make_sheet(folder: Path, out: Path, title: str) -> None:
    files = [name for name, _, _ in ICONS]
    cols = 6
    cell = 170
    header = 92
    rows = math.ceil(len(files) / cols)
    sheet = Image.new("RGB", (cols * cell + 30, rows * cell + header + 30), "#edf3f7")
    d = ImageDraw.Draw(sheet)
    font_title = ImageFont.load_default(size=30)
    font_label = ImageFont.load_default(size=14)
    d.text((24, 24), title, fill="#111827", font=font_title)
    for idx, name in enumerate(files):
        icon = Image.open(folder / name).convert("RGBA").resize((96, 96), Image.Resampling.LANCZOS)
        x = 24 + (idx % cols) * cell
        y = header + (idx // cols) * cell
        d.rounded_rectangle([x - 8, y - 8, x + 128, y + 142], radius=12, fill="#ffffff", outline="#d5e0e8")
        sheet.paste(icon, (x + 16, y), icon)
        d.text((x, y + 108), name.replace("Icon.png", ""), fill="#111827", font=font_label)
    sheet.save(out)


def main() -> None:
    FINALS.mkdir(parents=True, exist_ok=True)
    SHEETS.mkdir(parents=True, exist_ok=True)
    for idx, (filename, kind, palette) in enumerate(ICONS, 1):
        draw_icon(kind, palette, idx).save(FINALS / filename)

    if SOURCE.exists():
        make_sheet(SOURCE, SHEETS / "current-ios-theme-icons-reference.png", "Current theme icons reference")
    make_sheet(FINALS, SHEETS / "safe-ios-theme-icons-contact-sheet.png", "Safe replacement theme icons")


if __name__ == "__main__":
    main()
