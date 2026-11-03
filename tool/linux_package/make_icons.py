#!/usr/bin/env python3
"""Значки приложения из фирменного стиля (`docs/brand/`, задача С.1.4).

    python3 tool/linux_package/make_icons.py

Геометрия — `docs/brand/icon.svg` (белая скруглённая подложка со знаком
«10 из 20»), цвета — `docs/brand/colors.md`. Пишет значки для всех трёх ОС:

- `apps/app/linux/icons/` — `backpeer.svg`, `backpeer-<N>.png` (hicolor, 16–512)
  и `backpeer-tray.png` (знак без подложки для трея);
- `apps/app/macos/Runner/Assets.xcassets/AppIcon.appiconset/` — `app_icon_<N>.png`;
- `apps/app/windows/runner/resources/app_icon.ico`.

Нужен Pillow.
"""

import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
LINUX = ROOT / "apps/app/linux/icons"
MACOS = ROOT / "apps/app/macos/Runner/Assets.xcassets/AppIcon.appiconset"
WINDOWS = ROOT / "apps/app/windows/runner/resources"
ON, OFF, BG = "#0f6b5c", "#c9d2cd", "#ffffff"
LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_SIZES = [16, 32, 48, 64, 128, 256]


def cells():
    for row in range(4):
        for col in range(5):
            yield row, col, (row + col) % 2 == 0


def draw_mark(draw, unit):
    for row, col, filled in cells():
        x = (2 + col * 4) * unit
        y = (4 + row * 4) * unit
        draw.rounded_rectangle(
            [x, y, x + 3 * unit, y + 3 * unit],
            radius=0.6 * unit,
            fill=ON if filled else OFF,
        )


def svg() -> str:
    # Поле 23×23, как docs/brand/icon.svg: подложка со скруглением 4 и знаком.
    rects = "\n".join(
        f'  <rect x="{2 + col * 4}" y="{4 + row * 4}" width="3" height="3" '
        f'rx="0.6" fill="{ON if on else OFF}"/>'
        for row, col, on in cells()
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 23 23">\n'
        f'  <rect width="23" height="23" rx="4" fill="{BG}"/>\n'
        f"{rects}\n</svg>\n"
    )


def png(size, background, full_bleed=False):
    scale = 8
    big = size * scale
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    unit = big / 23
    if background:
        if full_bleed:
            draw.rectangle([0, 0, big - 1, big - 1], fill=BG)
        else:
            draw.rounded_rectangle(
                [0, 0, big - 1, big - 1], radius=4 * unit, fill=BG
            )
    draw_mark(draw, unit)
    return image.resize((size, size), Image.LANCZOS)


def write_linux():
    LINUX.mkdir(parents=True, exist_ok=True)
    (LINUX / "backpeer.svg").write_text(svg())
    for size in LINUX_SIZES:
        png(size, True).save(LINUX / f"backpeer-{size}.png", optimize=True)
    # Трей: без подложки, панель рисует свой фон.
    png(64, False).save(LINUX / "backpeer-tray.png", optimize=True)


def write_macos():
    MACOS.mkdir(parents=True, exist_ok=True)
    for size in MACOS_SIZES:
        # macOS сам скругляет углы — значок на весь холст, без прозрачности.
        png(size, True, full_bleed=True).save(
            MACOS / f"app_icon_{size}.png", optimize=True
        )


def write_windows():
    WINDOWS.mkdir(parents=True, exist_ok=True)
    frames = [png(size, True) for size in ICO_SIZES]
    frames[-1].save(
        WINDOWS / "app_icon.ico",
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
    )


def main():
    write_linux()
    write_macos()
    write_windows()


if __name__ == "__main__":
    main()
