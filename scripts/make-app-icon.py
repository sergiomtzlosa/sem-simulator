#!/usr/bin/env python3
"""Generate the brand-free SEM Simulator application icon.

The artwork is drawn procedurally so the repository contains no third-party
imagery. It depicts a dark instrument panel with an amber lens ring and a green
CRT-style micrograph of a spiky pollen grain.
"""

from __future__ import annotations

import math
import random
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 2048
CENTER = S // 2
ROOT = Path(__file__).resolve().parent.parent
ICONSET_NAME = "AppIcon.iconset"
OUTPUT = ROOT / "SEMSimulator" / "Resources" / "AppIcon.icns"
PREVIEW = ROOT / "docs" / "app-icon.png"


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask() -> Image.Image:
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((96, 96, S - 96, S - 96), radius=430, fill=255)
    return mask


def make_background() -> Image.Image:
    top = (47, 50, 45)
    bottom = (11, 13, 10)
    background = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(background)
    for y in range(S):
        t = y / (S - 1)
        draw.line((0, y, S, y), fill=(*lerp(top, bottom, t), 255))

    # A soft green bloom behind the lens.
    bloom = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bloom_draw = ImageDraw.Draw(bloom)
    for radius in range(940, 0, -24):
        alpha = round(22 * (1 - radius / 940) ** 2)
        bloom_draw.ellipse(
            (CENTER - radius, CENTER - radius, CENTER + radius, CENTER + radius),
            fill=(80, 180, 110, alpha),
        )
    background = Image.alpha_composite(background, bloom)

    # Fine horizontal brushed-metal texture.
    texture = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    texture_draw = ImageDraw.Draw(texture)
    for y in range(118, S - 118, 9):
        texture_draw.line((112, y, S - 112, y), fill=(255, 255, 255, 5))
    background = Image.alpha_composite(background, texture)

    background.putalpha(rounded_mask())
    return background


def make_screen() -> Image.Image:
    screen_radius = 620
    screen_box = (CENTER - screen_radius, CENTER - screen_radius,
                  CENTER + screen_radius, CENTER + screen_radius)
    screen_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(screen_mask).ellipse(screen_box, fill=255)

    screen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(screen)
    for radius in range(screen_radius, 0, -2):
        t = 1 - radius / screen_radius
        color = lerp((5, 17, 10), (34, 96, 51), t ** 1.7)
        draw.ellipse(
            (CENTER - radius, CENTER - radius, CENTER + radius, CENTER + radius),
            fill=(*color, 255),
        )

    # CRT scanlines.
    for y in range(CENTER - screen_radius, CENTER + screen_radius, 10):
        draw.line((CENTER - screen_radius, y, CENTER + screen_radius, y),
                  fill=(126, 255, 158, 18))

    # Edge vignette.
    vignette = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    vignette_draw = ImageDraw.Draw(vignette)
    for radius in range(screen_radius, screen_radius - 170, -2):
        alpha = round(110 * (radius - (screen_radius - 170)) / 170)
        vignette_draw.ellipse(
            (CENTER - radius, CENTER - radius, CENTER + radius, CENTER + radius),
            outline=(0, 0, 0, alpha), width=2,
        )
    screen = Image.alpha_composite(screen, vignette)

    # Amber scale bar.
    draw = ImageDraw.Draw(screen)
    bar_y = CENTER + 438
    bar_left, bar_right = CENTER - 250, CENTER + 250
    draw.line((bar_left, bar_y, bar_right, bar_y), fill=(222, 166, 74, 220), width=12)
    draw.line((bar_left, bar_y - 18, bar_left, bar_y + 18), fill=(222, 166, 74, 220), width=12)
    draw.line((bar_right, bar_y - 18, bar_right, bar_y + 18), fill=(222, 166, 74, 220), width=12)

    # Pollen grain.
    grain = make_pollen()
    screen = Image.alpha_composite(screen, grain)

    screen.putalpha(Image.composite(screen.getchannel("A"), Image.new("L", (S, S), 0), screen_mask))
    return screen


def make_pollen() -> Image.Image:
    cx, cy = CENTER, CENTER - 28
    radius = 246
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(1987)

    # Spikes around the exine.
    spikes = 32
    for index in range(spikes):
        angle = 2 * math.pi * index / spikes
        half = (2 * math.pi / spikes) * 0.62
        tip_radius = radius + 62 + 18 * math.sin(index * 1.9)
        points = [
            (cx + radius * math.cos(angle - half), cy + radius * math.sin(angle - half)),
            (cx + tip_radius * math.cos(angle), cy + tip_radius * math.sin(angle)),
            (cx + radius * math.cos(angle + half), cy + radius * math.sin(angle + half)),
        ]
        draw.polygon(points, fill=(44, 126, 62, 255), outline=(10, 39, 21, 255))

    body_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body_mask).ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius), fill=255
    )

    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body_draw = ImageDraw.Draw(body)
    body_draw.ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius), fill=(58, 156, 82, 255)
    )
    for highlight_radius in range(radius, 0, -3):
        t = 1 - highlight_radius / radius
        alpha = round(190 * t ** 2.2)
        offset = 82 * (1 - highlight_radius / radius)
        body_draw.ellipse(
            (
                cx - 58 - offset - highlight_radius * 0.56,
                cy - 76 - offset - highlight_radius * 0.56,
                cx - 58 - offset + highlight_radius * 0.56,
                cy - 76 - offset + highlight_radius * 0.56,
            ),
            fill=(206, 255, 190, alpha),
        )

    # Surface texture, pores, and ridges.
    for _ in range(120):
        angle = rng.random() * 2 * math.pi
        distance = math.sqrt(rng.random()) * (radius - 22)
        x = cx + distance * math.cos(angle)
        y = cy + distance * math.sin(angle)
        size = rng.randint(5, 22)
        tone = rng.choice(
            [(21, 82, 40, 150), (104, 224, 123, 110), (168, 255, 158, 80)]
        )
        body_draw.ellipse((x - size, y - size, x + size, y + size), fill=tone)

    for angle, distance, size in [
        (-2.45, 110, 34), (-0.8, 145, 24), (0.55, 96, 28),
        (1.8, 155, 20), (2.6, 80, 18),
    ]:
        x = cx + distance * math.cos(angle)
        y = cy + distance * math.sin(angle)
        body_draw.ellipse((x - size, y - size, x + size, y + size), fill=(12, 55, 27, 190))
        body_draw.ellipse(
            (x - size + 5, y - size + 5, x + size - 5, y + size - 5),
            fill=(35, 104, 51, 210),
        )

    body.putalpha(Image.composite(body.getchannel("A"), Image.new("L", (S, S), 0), body_mask))
    layer = Image.alpha_composite(layer, body)

    # Crisp exine outline.
    outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(outline).ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius),
        outline=(8, 34, 18, 255), width=9,
    )
    layer = Image.alpha_composite(layer, outline)

    # Electron-beam highlight.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_center = (cx - 82, cy - 104)
    for glow_radius in range(150, 0, -3):
        alpha = round(125 * (1 - glow_radius / 150) ** 2)
        glow_draw.ellipse(
            (
                glow_center[0] - glow_radius,
                glow_center[1] - glow_radius,
                glow_center[0] + glow_radius,
                glow_center[1] + glow_radius,
            ),
            fill=(224, 255, 214, alpha),
        )
    layer = Image.alpha_composite(layer, glow)
    return layer


def make_icon() -> Image.Image:
    icon = make_background()

    # Amber halo behind the lens ring.
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    for width in range(38, 0, -2):
        alpha = round(40 * (1 - width / 38))
        halo_draw.ellipse(
            (CENTER - 704, CENTER - 704, CENTER + 704, CENTER + 704),
            outline=(224, 168, 78, alpha), width=width,
        )
    halo = halo.filter(ImageFilter.GaussianBlur(10))
    icon = Image.alpha_composite(icon, halo)

    draw = ImageDraw.Draw(icon)

    # Lens housing.
    draw.ellipse((CENTER - 704, CENTER - 704, CENTER + 704, CENTER + 704),
                 fill=(20, 22, 18, 255), outline=(126, 118, 100, 255), width=8)
    draw.ellipse((CENTER - 680, CENTER - 680, CENTER + 680, CENTER + 680),
                 outline=(205, 154, 68, 255), width=20)
    draw.ellipse((CENTER - 650, CENTER - 650, CENTER + 650, CENTER + 650),
                 fill=(8, 11, 8, 255), outline=(82, 76, 63, 255), width=6)

    # Aperture ticks around the ring.
    for index in range(12):
        angle = 2 * math.pi * index / 12
        inner = 660
        outer = 690 if index % 3 else 698
        draw.line(
            (
                CENTER + inner * math.cos(angle),
                CENTER + inner * math.sin(angle),
                CENTER + outer * math.cos(angle),
                CENTER + outer * math.sin(angle),
            ),
            fill=(222, 174, 90, 220),
            width=9,
        )

    screen = make_screen()
    icon = Image.alpha_composite(icon, screen)

    # Inner glass rim.
    draw = ImageDraw.Draw(icon)
    draw.ellipse((CENTER - 620, CENTER - 620, CENTER + 620, CENTER + 620),
                 outline=(160, 224, 174, 55), width=5)

    icon.putalpha(rounded_mask())
    return icon


def save_iconset(master: Image.Image, directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    sizes = [16, 32, 128, 256, 512]
    for size in sizes:
        master.resize((size, size), Image.LANCZOS).save(directory / f"icon_{size}x{size}.png")
        master.resize((size * 2, size * 2), Image.LANCZOS).save(
            directory / f"icon_{size}x{size}@2x.png"
        )


def main() -> None:
    master = make_icon()
    preview = master.resize((1024, 1024), Image.LANCZOS)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    preview.save(PREVIEW)

    with tempfile.TemporaryDirectory() as temp:
        iconset = Path(temp) / ICONSET_NAME
        save_iconset(preview, iconset)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUTPUT)], check=True)
    print(f"Wrote {OUTPUT}")
    print(f"Wrote {PREVIEW}")


if __name__ == "__main__":
    main()
