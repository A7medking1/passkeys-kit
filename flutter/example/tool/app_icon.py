"""Draws the example app's icon (a fingerprint on an indigo to violet
gradient) and writes every size iOS and Android ask for.

Run it from flutter/example (needs Pillow):

    python3 tool/app_icon.py
"""

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

EXAMPLE = Path(__file__).resolve().parent.parent
INDIGO = (79, 70, 229)  # 4F46E5
PURPLE = (147, 51, 234)  # 9333EA
FINGERPRINT = ""  # Icons.fingerprint in the Material Icons font

ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def material_icons_font() -> Path:
    flutter = Path(shutil.which("flutter")).resolve()
    return flutter.parent.parent / "bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"


def gradient(size: int) -> Image.Image:
    # Top-left indigo to bottom-right purple, built from a 1-pixel ramp.
    ramp = Image.new("RGB", (256, 1))
    for i in range(256):
        t = i / 255
        ramp.putpixel((i, 0), tuple(round(a + (b - a) * t) for a, b in zip(INDIGO, PURPLE)))
    ramp = ramp.resize((size * 2, size * 2)).rotate(-45, resample=Image.BICUBIC)
    offset = size // 2
    return ramp.crop((offset, offset, offset + size, offset + size))


def white(alpha: Image.Image) -> Image.Image:
    """A white layer shaped by `alpha`. Blurring only the alpha keeps the
    edges white: blurring RGBA over transparent black would darken them."""
    layer = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    layer.putalpha(alpha)
    return layer


def master(size: int = 1024) -> Image.Image:
    icon = gradient(size).convert("RGBA")

    # A soft light in the top-left corner.
    light = Image.new("L", (size, size), 0)
    ImageDraw.Draw(light).ellipse(
        (-size * 0.35, -size * 0.45, size * 0.75, size * 0.55), fill=60
    )
    icon = Image.alpha_composite(icon, white(light.filter(ImageFilter.GaussianBlur(size * 0.1))))

    # The fingerprint, with a faint glow under it.
    font = ImageFont.truetype(str(material_icons_font()), round(size * 0.6))
    glyph = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glyph).text((size / 2, size / 2), FINGERPRINT, font=font, fill=255, anchor="mm")
    glow = glyph.filter(ImageFilter.GaussianBlur(size * 0.035)).point(lambda a: round(a * 0.5))
    icon = Image.alpha_composite(icon, white(glow))
    return Image.alpha_composite(icon, white(glyph))


def write_ios(icon: Image.Image) -> None:
    folder = EXAMPLE / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((folder / "Contents.json").read_text())
    for image in contents["images"]:
        points = float(image["size"].split("x")[0])
        pixels = round(points * int(image["scale"].rstrip("x")))
        # iOS rounds the corners itself, and refuses icons with transparency.
        icon.resize((pixels, pixels), Image.LANCZOS).convert("RGB").save(folder / image["filename"])


def write_android(icon: Image.Image) -> None:
    for density, pixels in ANDROID_SIZES.items():
        scale = 4
        mask = Image.new("L", (pixels * scale, pixels * scale), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, pixels * scale - 1, pixels * scale - 1), radius=pixels * scale * 0.23, fill=255
        )
        rounded = icon.resize((pixels * scale, pixels * scale), Image.LANCZOS)
        rounded.putalpha(mask)
        target = EXAMPLE / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        rounded.resize((pixels, pixels), Image.LANCZOS).save(target)


if __name__ == "__main__":
    icon = master()
    write_ios(icon)
    write_android(icon)
    icon.convert("RGB").save(EXAMPLE / "tool/app_icon.png")
    print("Wrote the iOS and Android icons, and tool/app_icon.png")
