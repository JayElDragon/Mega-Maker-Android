"""Replace the existing legacy and adaptive launcher icon bitmaps."""

import argparse
from copy import copy
from io import BytesIO
from pathlib import Path
from shutil import copyfileobj
from zipfile import ZipFile

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps


LEGACY = {"9T", "2H", "yj", "8p", "9X", "-t", "2c"}
BACKGROUND = {"fj", "w6", "D8", "XF", "5k", "rx"}
FOREGROUND = {"M6", "A1", "_U", "is", "yX", "Wc"}


def icon_for(source, size, layer):
    if layer in LEGACY:
        return source.resize(size, Image.Resampling.LANCZOS)
    # Adaptive icon: the Odin launcher cuts the middle 72/108 of the layers
    # into a circle. The background is the artwork's own striped backdrop,
    # blown up and blurred, so the whole circle is filled; the artwork sits
    # on top at ICON_SCALE so the MEGA MAKER letters fit inside the circle.
    art = full_bleed(source)
    if layer in BACKGROUND:
        # The artwork's left edge is its orange stripes: stretch that strip.
        strip = art.crop((0, 0, max(1, art.width // 25), art.height))
        return strip.resize(size, Image.Resampling.BILINEAR).filter(ImageFilter.GaussianBlur(min(size) / 200))
    icon_size = round(min(size) * ICON_SCALE / 108)
    icon = art.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    # Soft edge so the artwork melts into the blurred backdrop.
    edge = max(2, icon_size // 24)
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rectangle((edge, edge, icon_size - 1 - edge, icon_size - 1 - edge), fill=255)
    icon.putalpha(mask.filter(ImageFilter.GaussianBlur(edge)))
    canvas = Image.new("RGBA", size)
    canvas.paste(icon, ((size[0] - icon_size) // 2, (size[1] - icon_size) // 2), icon)
    return canvas


ICON_SCALE = 58


def full_bleed(source):
    """The square artwork without its outer outline and rounded corners."""
    inset = round(source.width * 0.03)
    art = source.crop((inset, inset, source.width - inset, source.height - inset))
    filled = art.resize((8, 8), Image.Resampling.BOX).resize(art.size, Image.Resampling.BILINEAR)
    filled.alpha_composite(art)
    filled.putalpha(255)
    return filled


def trim_black_border(image):
    image = image.convert("RGBA")
    red, green, blue, alpha = image.split()
    brightness = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    dark = brightness.point(lambda value: 255 if value < 56 else 0)
    exterior = ImageOps.expand(dark, border=1, fill=255)
    ImageDraw.floodfill(exterior, (0, 0), 128)
    exterior = exterior.crop((1, 1, 1 + image.width, 1 + image.height))
    retained = exterior.point(lambda value: 0 if value == 128 else 255)
    image.putalpha(ImageChops.multiply(alpha, retained))
    bounds = image.getbbox()
    if bounds is None:
        raise ValueError("The launcher icon has no visible artwork")
    image = image.crop(bounds)
    edge = max(image.size)
    square = Image.new("RGBA", (edge, edge))
    square.paste(image, ((edge - image.width) // 2, (edge - image.height) // 2))
    return square


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("image", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    with Image.open(args.image) as image:
        source = trim_black_border(image)
    layers = {f"res/{name}.png": name for name in LEGACY | BACKGROUND | FOREGROUND}
    with ZipFile(args.apk) as original, ZipFile(args.output, "w") as updated:
        if not layers.keys() <= set(original.namelist()):
            raise ValueError("APK does not have the expected launcher icon resources")
        for entry in original.infolist():
            if entry.filename.startswith("META-INF/") and entry.filename.upper().endswith(
                (".SF", ".RSA", ".DSA", ".EC", "MANIFEST.MF")
            ):
                continue
            if entry.filename in layers:
                with Image.open(BytesIO(original.read(entry))) as previous:
                    icon = icon_for(source, previous.size, layers[entry.filename])
                buffer = BytesIO()
                icon.save(buffer, "PNG", optimize=True)
                updated.writestr(copy(entry), buffer.getvalue())
            else:
                with original.open(entry) as read, updated.open(copy(entry), "w") as write:
                    copyfileobj(read, write)


if __name__ == "__main__":
    main()
