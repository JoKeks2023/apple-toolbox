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


def tv_layer(width, height, layer):
    """tvOS parallax layers: gradient back layer and a transparent glyph front layer."""
    if layer == "Back":
        return gradient(max(width, height), BLUE, VIOLET).resize((width, height), Image.LANCZOS)
    side = round(height * 0.9)
    mark = glyph(side * SS, (255, 255, 255, 255), (255, 255, 255, 110), (58, 90, 230, 255))
    mark = mark.resize((side, side), Image.LANCZOS)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(mark, ((width - side) // 2, (height - side) // 2))
    return canvas


def top_shelf(width, height):
    base = gradient(max(width, height), BLUE, VIOLET).resize((width, height), Image.LANCZOS)
    side = round(height * 0.8)
    mark = glyph(side * 2, (255, 255, 255, 255), (255, 255, 255, 110), (58, 90, 230, 255)).resize((side, side), Image.LANCZOS)
    base.alpha_composite(mark, (round(width * 0.08), (height - side) // 2))
    return base


def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


def write_tv_brand_assets():
    info = {"author": "xcode", "version": 1}
    brand = os.path.join(ASSETS, "App Icon & Top Shelf Image.brandassets")
    stacks = (("App Icon - App Store", 1280, 768, (1,)), ("App Icon", 400, 240, (1, 2)))
    for name, width, height, scales in stacks:
        stack = os.path.join(brand, f"{name}.imagestack")
        write_json(os.path.join(stack, "Contents.json"),
                   {"info": info, "layers": [{"filename": "Front.imagestacklayer"}, {"filename": "Back.imagestacklayer"}]})
        for layer in ("Front", "Back"):
            layer_dir = os.path.join(stack, f"{layer}.imagestacklayer")
            write_json(os.path.join(layer_dir, "Contents.json"), {"info": info})
            imageset = os.path.join(layer_dir, "Content.imageset")
            images = []
            for scale in scales:
                file = f"{layer.lower()}@{scale}x.png"
                os.makedirs(imageset, exist_ok=True)
                tv_layer(width * scale, height * scale, layer).save(os.path.join(imageset, file))
                images.append({"filename": file, "idiom": "tv", "scale": f"{scale}x"})
            write_json(os.path.join(imageset, "Contents.json"), {"images": images, "info": info})
    shelves = (("Top Shelf Image", "top-shelf-image", 1920, 720), ("Top Shelf Image Wide", "top-shelf-image-wide", 2320, 720))
    for name, _, width, height in shelves:
        imageset = os.path.join(brand, f"{name}.imageset")
        os.makedirs(imageset, exist_ok=True)
        images = []
        for scale in (1, 2):
            file = f"top-shelf@{scale}x.png"
            top_shelf(width * scale, height * scale).convert("RGB").save(os.path.join(imageset, file))
            images.append({"filename": file, "idiom": "tv", "scale": f"{scale}x"})
        write_json(os.path.join(imageset, "Contents.json"), {"images": images, "info": info})
    write_json(os.path.join(brand, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": info,
    })


def write_readme_icon():
    """Rounded app icon for the README header (docs/assets/app-icon.png)."""
    size, radius = 256, 57
    icon = render(size, "light")
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=radius * SS, fill=255)
    icon.putalpha(mask.resize((size, size), Image.LANCZOS))
    folder = os.path.join(ROOT, "docs", "assets")
    os.makedirs(folder, exist_ok=True)
    icon.save(os.path.join(folder, "app-icon.png"))


if __name__ == "__main__":
    write_appicon()
    write_tv_brand_assets()
    write_readme_icon()
