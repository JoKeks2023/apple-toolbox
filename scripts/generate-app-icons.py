#!/usr/bin/env python3
"""Generate the Apple Toolbox app icons from one set of shapes.

  AppleToolbox/AppIcon.icon     Icon Composer document (iOS, iPadOS, macOS, watchOS). The system renders it with
                                Liquid Glass and derives the dark, tinted and clear appearances; Xcode derives the
                                images for older OS versions.
  App Icon & Top Shelf Image    tvOS parallax layers (Icon Composer has no tvOS), drawn with Pillow.
  docs/assets/app-icon*.png     README header, exported from the .icon with Icon Composer's ictool.

The glyph is drawn here on purpose: SF Symbols may not be used in app icons (SF Symbols license).
Requires Xcode 26+ and Pillow (`pip3 install pillow`). Run from the repository root:
    python3 scripts/generate-app-icons.py
"""
import json
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ICON = os.path.join(ROOT, "AppleToolbox", "AppIcon.icon")
ASSETS = os.path.join(ROOT, "AppleToolbox", "Assets.xcassets")
SS = 4  # supersampling factor for the Pillow renders

BLUE = (61, 128, 255)
VIOLET = (128, 64, 255)

# Shapes in the 1024 × 1024 icon grid.
BODY = dict(left=196, right=828, top=424, bottom=804, radius=100)
SEAM = (540, 570)                      # gap between lid and base
HANDLE = ((370, 292, 654, 470, 66), (418, 340, 606, 470, 22))   # outer, inner rounded rect (x0, y0, x1, y1, r)
LATCH = (452, 500, 572, 612, 32)
SPARKLE = dict(cx=800, cy=226, r=100, k=18)


# MARK: - Geometry

def sparkle_points(scale, steps=24):
    """Four-point star with inward-curving sides (quadratic curves through the control point near the center)."""
    cx, cy, r, k = (SPARKLE[key] * scale for key in ("cx", "cy", "r", "k"))
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    controls = [(cx + k, cy - k), (cx + k, cy + k), (cx - k, cy + k), (cx - k, cy - k)]
    points = []
    for i in range(4):
        (x0, y0), (qx, qy), (x1, y1) = tips[i], controls[i], tips[(i + 1) % 4]
        for step in range(steps):
            t = step / steps
            points.append(((1 - t) ** 2 * x0 + 2 * (1 - t) * t * qx + t * t * x1,
                           (1 - t) ** 2 * y0 + 2 * (1 - t) * t * qy + t * t * y1))
    return points


def svg_rounded_rect(x0, y0, x1, y1, r):
    return (f"M{x0 + r} {y0}H{x1 - r}A{r} {r} 0 0 1 {x1} {y0 + r}V{y1 - r}A{r} {r} 0 0 1 {x1 - r} {y1}"
            f"H{x0 + r}A{r} {r} 0 0 1 {x0} {y1 - r}V{y0 + r}A{r} {r} 0 0 1 {x0 + r} {y0}Z")


def svg_paths():
    """SVG paths per layer; every path is filled on its own, so overlapping paths add up."""
    l, r, t, b, cr = (BODY[key] for key in ("left", "right", "top", "bottom", "radius"))
    lid = f"M{l + cr} {t}H{r - cr}A{cr} {cr} 0 0 1 {r} {t + cr}V{SEAM[0]}H{l}V{t + cr}A{cr} {cr} 0 0 1 {l + cr} {t}Z"
    base = f"M{l} {SEAM[1]}H{r}V{b - cr}A{cr} {cr} 0 0 1 {r - cr} {b}H{l + cr}A{cr} {cr} 0 0 1 {l} {b - cr}Z"
    handle = svg_rounded_rect(*HANDLE[0]) + svg_rounded_rect(*HANDLE[1])
    c, k, rr = SPARKLE["cx"], SPARKLE["k"], SPARKLE["r"]
    y = SPARKLE["cy"]
    sparkle = (f"M{c} {y - rr}Q{c + k} {y - k} {c + rr} {y}Q{c + k} {y + k} {c} {y + rr}"
               f"Q{c - k} {y + k} {c - rr} {y}Q{c - k} {y - k} {c} {y - rr}Z")
    return {"box": [handle, lid, base], "latch": [svg_rounded_rect(*LATCH)], "sparkle": [sparkle]}


def mask(size, layer):
    """Anti-aliased alpha mask of a layer, `size` pixels square."""
    big = size * SS
    s = big / 1024
    m = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(m)
    box = lambda x0, y0, x1, y1: [round(x0 * s), round(y0 * s), round(x1 * s), round(y1 * s)]
    if layer == "box":
        (hx0, hy0, hx1, hy1, hr), (ix0, iy0, ix1, iy1, ir) = HANDLE
        d.rounded_rectangle(box(hx0, hy0, hx1, hy1), radius=round(hr * s), fill=255)
        d.rounded_rectangle(box(ix0, iy0, ix1, iy1), radius=round(ir * s), fill=0)
        l, r, t, b, cr = (BODY[key] for key in ("left", "right", "top", "bottom", "radius"))
        d.rounded_rectangle(box(l, t, r, SEAM[0]), radius=round(cr * s), fill=255, corners=(True, True, False, False))
        d.rounded_rectangle(box(l, SEAM[1], r, b), radius=round(cr * s), fill=255, corners=(False, False, True, True))
    elif layer == "latch":
        x0, y0, x1, y1, r = LATCH
        d.rounded_rectangle(box(x0, y0, x1, y1), radius=round(r * s), fill=255)
    elif layer == "sparkle":
        d.polygon(sparkle_points(s), fill=255)
    return m.resize((size, size), Image.LANCZOS)


# MARK: - Icon Composer document

def color(rgb):
    return "extended-srgb:" + ",".join(f"{c / 255:.5f}" for c in rgb) + ",1.00000"


def write_icon_document():
    assets = os.path.join(ICON, "Assets")
    os.makedirs(assets, exist_ok=True)
    for name, paths in svg_paths().items():
        body = "".join(f'<path fill="#FFFFFF" fill-rule="evenodd" d="{d}"/>' for d in paths)
        with open(os.path.join(assets, f"{name}.svg"), "w") as f:
            f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>\n')

    def group(name):
        # One glass layer per group, front to back, so each piece gets its own depth, highlight and shadow.
        return {"layers": [{"glass": True, "image-name": f"{name}.svg", "name": name}],
                "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": True, "value": 0.5}}

    document = {
        "fill": {"linear-gradient": [color(BLUE), color(VIOLET)],
                 "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}},
        "groups": [group("sparkle"), group("latch"), group("box")],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    write_json(os.path.join(ICON, "icon.json"), document)


def ictool():
    developer = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip()
    return os.path.join(os.path.dirname(developer), "Applications", "Icon Composer.app", "Contents", "Executables", "ictool")


def export(path, rendition, size, platform="iOS"):
    subprocess.run([ictool(), ICON, "--export-image", "--output-file", path, "--platform", platform, "--rendition", rendition,
                    "--width", str(size), "--height", str(size), "--scale", "1"], check=True, capture_output=True)


def write_readme_icons():
    folder = os.path.join(ROOT, "docs", "assets")
    os.makedirs(folder, exist_ok=True)
    export(os.path.join(folder, "app-icon.png"), "Default", 256)
    export(os.path.join(folder, "app-icon-dark.png"), "Dark", 256)


# MARK: - tvOS

def gradient(width, height):
    img = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line([(0, y), (width, y)], fill=tuple(round(BLUE[i] + (VIOLET[i] - BLUE[i]) * t) for i in range(3)) + (255,))
    return img


def glyph(size, layers, fills, shadow=True):
    """White (or tinted) layers with a soft drop shadow, like the glass groups on the other platforms."""
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for layer in layers:
        alpha = mask(size, layer)
        if shadow:
            offset = round(size * 0.012)
            blurred = alpha.filter(ImageFilter.GaussianBlur(size * 0.016)).point(lambda a: a * 0.28)
            shade = Image.new("RGBA", (size, size), (20, 10, 60, 0))
            shade.putalpha(blurred)
            out.alpha_composite(shade, (0, offset))
        solid = Image.new("RGBA", (size, size), fills.get(layer, (255, 255, 255)) + (255,))
        solid.putalpha(alpha)
        out.alpha_composite(solid)
    return out


def tv_layer(width, height, layer):
    """Back: gradient. Middle: toolbox. Front: latch and sparkle. tvOS adds the parallax and the highlight."""
    if layer == "Back":
        return gradient(width, height)
    side = round(height * 0.92)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    parts = ["box"] if layer == "Middle" else ["latch", "sparkle"]
    canvas.alpha_composite(glyph(side, parts, {"latch": (236, 238, 255)}), ((width - side) // 2, (height - side) // 2))
    return canvas


def top_shelf(width, height):
    base = gradient(width, height)
    side = round(height * 0.8)
    base.alpha_composite(glyph(side, ["box", "latch", "sparkle"], {"latch": (236, 238, 255)}),
                         (round(width * 0.08), (height - side) // 2))
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
    layers = ("Front", "Middle", "Back")
    for name, width, height, scales in stacks:
        stack = os.path.join(brand, f"{name}.imagestack")
        write_json(os.path.join(stack, "Contents.json"),
                   {"info": info, "layers": [{"filename": f"{layer}.imagestacklayer"} for layer in layers]})
        for layer in layers:
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
    shelves = (("Top Shelf Image", 1920, 720), ("Top Shelf Image Wide", 2320, 720))
    for name, width, height in shelves:
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


if __name__ == "__main__":
    write_icon_document()
    write_tv_brand_assets()
    write_readme_icons()
