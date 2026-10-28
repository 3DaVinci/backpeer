#!/usr/bin/env python3
"""Временные значки приложения до стиля продукта (С.1.4): та же сетка
квадратов, что у значка сайта (apps/site/public/favicon.svg).

    python3 tool/linux_package/make_icons.py

Пишет apps/app/linux/icons/: file-storage.svg, file-storage-<N>.png для
пакетов (hicolor) и file-storage-tray.png для значка в трее. Нужен Pillow.
"""

import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/app/linux/icons"
ON, OFF, BG = "#0f6b5c", "#c9d2cd", "#ffffff"
SIZES = [16, 24, 32, 48, 64, 128, 256, 512]


def cells():
    for row in range(4):
        for col in range(5):
            yield row, col, (row + col) % 2 == 0


def svg() -> str:
    # Поле 23×23, как у сайта: сетка 19×15 с полями.
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


def png(size: int, background: bool) -> Image.Image:
    scale = 8
    big = size * scale
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    unit = big / 23
    if background:
        draw.rounded_rectangle([0, 0, big - 1, big - 1], radius=4 * unit, fill=BG)
    for row, col, on in cells():
        x = (2 + col * 4) * unit
        y = (4 + row * 4) * unit
        draw.rounded_rectangle(
            [x, y, x + 3 * unit, y + 3 * unit],
            radius=0.6 * unit,
            fill=ON if on else OFF,
        )
    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "file-storage.svg").write_text(svg())
    for size in SIZES:
        png(size, True).save(OUT / f"file-storage-{size}.png", optimize=True)
    # Трей: без подложки, панель рисует свой фон.
    png(64, False).save(OUT / "file-storage-tray.png", optimize=True)


if __name__ == "__main__":
    main()
