#!/usr/bin/env python3
"""Render the Apple Toolbox app icons into AppleToolbox/Assets.xcassets.

Requires Pillow (`pip3 install pillow`). Run from the repository root:
    python3 scripts/generate-app-icons.py
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(ROOT, "AppleToolbox", "Assets.xcassets")
SS = 4  # supersampling factor for smooth edges

BLUE = (58, 123, 255)
VIOLET = (123, 60, 255)


def gradient(size, top, bottom):
    img = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        draw.line([(0, y), (size, y)], fill=color)
    return img


def glyph(size, body, band, accent):
    """Toolbox with handle, latch and a discovery sparkle, drawn in a 1024 grid."""
    s = size / 1024
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = lambda x0, y0, x1, y1: [round(x0 * s), round(y0 * s), round(x1 * s), round(y1 * s)]
    d.rounded_rectangle(box(402, 290, 622, 470), radius=round(56 * s), outline=body, width=round(46 * s))
    d.rounded_rectangle(box(222, 410, 802, 790), radius=round(72 * s), fill=body)
    d.rectangle(box(222, 500, 802, 548), fill=band)
    d.rounded_rectangle(box(462, 470, 562, 580), radius=round(24 * s), fill=accent)
    cx, cy, r, w = 780 * s, 250 * s, 92 * s, 24 * s
    d.polygon([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w),
               (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w)], fill=body)
    return layer


def render(size, variant):
    big = size * SS
    if variant == "light":
        base = gradient(big, BLUE, VIOLET)
        mark = glyph(big, (255, 255, 255, 255), (255, 255, 255, 110), (58, 90, 230, 255))
    elif variant == "dark":
        base = gradient(big, (30, 32, 44), (12, 12, 18))
        mark = glyph(big, (110, 150, 255, 255), (150, 110, 255, 255), (30, 32, 44, 255))
    elif variant == "tinted":
        base = Image.new("RGBA", (big, big), (0, 0, 0, 255))
        mark = glyph(big, (235, 235, 235, 255), (140, 140, 140, 255), (0, 0, 0, 255))
    else:
        raise ValueError(variant)
    base.alpha_composite(mark)
    return base.resize((size, size), Image.LANCZOS)


def render_mac(size):
    """macOS icons sit on a rounded tile inside the 1024 grid with a soft shadow."""
    inset, radius, tile_size = 100, 185, 824
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([inset, inset + 12, 1024 - inset, 1024 - inset + 12],
                                             radius=radius, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    mask = Image.new("L", (tile_size * SS, tile_size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile_size * SS - 1, tile_size * SS - 1], radius=radius * SS, fill=255)
    mask = mask.resize((tile_size, tile_size), Image.LANCZOS)
    canvas.paste(render(tile_size, "light"), (inset, inset), mask)
    return canvas.resize((size, size), Image.LANCZOS)


def write_appicon():
    folder = os.path.join(ASSETS, "AppIcon.appiconset")
    images = []
    for variant, appearance in (("light", None), ("dark", "dark"), ("tinted", "tinted")):
        name = f"icon-ios-{variant}.png"
        render(1024, variant).convert("RGB").save(os.path.join(folder, name))
        entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)
    watch = "icon-watchos.png"
    render(1024, "light").convert("RGB").save(os.path.join(folder, watch))
    images.append({"filename": watch, "idiom": "universal", "platform": "watchos", "size": "1024x1024"})
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon-mac-{points}@{scale}x.png"
            render_mac(points * scale).save(os.path.join(folder, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    write_appicon()
