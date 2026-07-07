#!/usr/bin/env python3
"""Generate the tvOS brand assets (App Icon layers + Top Shelf images) from the
PatreonTV logos.

Composites the transparent source logos in scripts/brand/ into the layered
`.brandassets` the tvOS app icon requires:
  - App icon = 3 layers (opaque Back gradient, empty Middle, Front = "P TV" mark)
  - Top Shelf = wordmark centered on an opaque dark background

Per Apple's HIG: the background layer must be opaque; keep foreground art inside
a safe zone (the system crops foreground layers on focus).

Requires Pillow.  Run manually when the logo changes, then commit the output:
    python3 -m venv .venv && .venv/bin/pip install Pillow
    .venv/bin/python scripts/generate-brand-assets.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "PatreonTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
SRC = Path(__file__).resolve().parent / "brand"

MARK = Image.open(SRC / "ptv_mark.png").convert("RGBA")
WORDMARK = Image.open(SRC / "ptv_wordmark.png").convert("RGBA")

# Dark, slightly purple background gradient (top -> bottom).
BG_TOP = (28, 14, 40)
BG_BOTTOM = (8, 4, 12)


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def gradient(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = round(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
        g = round(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
        b = round(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return img


def fitted(logo: Image.Image, size: tuple[int, int], frac: float) -> Image.Image:
    """Center `logo` on a transparent canvas, scaled to `frac` of the canvas."""
    w, h = size
    max_w, max_h = int(w * frac), int(h * frac)
    scale = min(max_w / logo.width, max_h / logo.height)
    resized = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((w - resized.width) // 2, (h - resized.height) // 2))
    return canvas


def transparent(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, (0, 0, 0, 0))


def layer_imageset(stack_dir: Path, name: str, image_1x: Image.Image) -> None:
    layer_dir = stack_dir / f"{name}.imagestacklayer"
    imageset = layer_dir / "Content.imageset"
    write_json(layer_dir / "Contents.json", {"info": {"version": 1, "author": "xcode"}})
    write_json(
        imageset / "Contents.json",
        {
            "images": [
                {"filename": f"{name.lower()}.png", "idiom": "tv", "scale": "1x"},
                {"filename": f"{name.lower()}@2x.png", "idiom": "tv", "scale": "2x"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
    )
    imageset.mkdir(parents=True, exist_ok=True)
    image_1x.save(imageset / f"{name.lower()}.png")
    image_1x.resize((image_1x.width * 2, image_1x.height * 2), Image.LANCZOS).save(
        imageset / f"{name.lower()}@2x.png"
    )


def make_icon(name: str, size: tuple[int, int]) -> None:
    stack = BRAND / f"{name}.imagestack"
    write_json(
        stack / "Contents.json",
        {
            "layers": [
                {"filename": "Front.imagestacklayer"},
                {"filename": "Middle.imagestacklayer"},
                {"filename": "Back.imagestacklayer"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
    )
    layer_imageset(stack, "Back", gradient(size))            # opaque background
    layer_imageset(stack, "Middle", transparent(size))       # empty
    layer_imageset(stack, "Front", fitted(MARK, size, 0.72)) # the mark, in the safe zone


def make_top_shelf(name: str, size: tuple[int, int]) -> None:
    imageset = BRAND / f"{name}.imageset"
    slug = name.lower().replace(" ", "-")
    bg = gradient(size)
    bg.alpha_composite(fitted(WORDMARK, size, 0.55))
    write_json(
        imageset / "Contents.json",
        {
            "images": [
                {"filename": f"{slug}.png", "idiom": "tv", "scale": "1x"},
                {"filename": f"{slug}@2x.png", "idiom": "tv", "scale": "2x"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
    )
    imageset.mkdir(parents=True, exist_ok=True)
    bg.save(imageset / f"{slug}.png")
    bg.resize((size[0] * 2, size[1] * 2), Image.LANCZOS).save(imageset / f"{slug}@2x.png")


def main() -> None:
    make_icon("App Icon", (400, 240))
    make_icon("App Icon - App Store", (1280, 768))
    make_top_shelf("Top Shelf Image", (1920, 720))
    make_top_shelf("Top Shelf Image Wide", (2320, 720))
    print(f"Wrote branded tvOS assets to {BRAND}")


if __name__ == "__main__":
    main()
