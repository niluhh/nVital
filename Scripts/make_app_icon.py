#!/usr/bin/env python3
"""Draws the nVital app icon: an ECG trace on a patient-monitor screen.

Writes every size of nVital/Assets.xcassets/AppIcon.appiconset.
Requires Pillow:

    python3 -m pip install pillow
    python3 Scripts/make_app_icon.py
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "nVital", "Assets.xcassets", "AppIcon.appiconset")

SUPERSAMPLE = 4096  # drawn at 4x, then reduced for smooth edges
K = SUPERSAMPLE / 1024  # all coordinates below are on a 1024-point canvas

BACKGROUND_TOP = (18, 56, 79)
BACKGROUND_BOTTOM = (6, 18, 29)
TRACE_LEFT = (20, 200, 212)
TRACE_RIGHT = (76, 242, 138)


def scaled(points):
    return [(x * K, y * K) for x, y in points]


def rounded_square(size=824, corner=296, exponent=3.4, steps=90):
    """macOS icon tile: straight sides and smooth ("continuous") corners.

    Each corner is a superellipse quarter; with these values its depth matches
    the 185 pt corner radius of Apple's 824 pt icon grid.
    """
    left, top = 512 - size / 2, 512 - size / 2
    right, bottom = 512 + size / 2, 512 + size / 2
    power = 2 / exponent
    points = []
    corners = [
        (right - corner, top + corner, lambda u: (math.sin(u) ** power, -math.cos(u) ** power)),
        (right - corner, bottom - corner, lambda u: (math.cos(u) ** power, math.sin(u) ** power)),
        (left + corner, bottom - corner, lambda u: (-math.sin(u) ** power, math.cos(u) ** power)),
        (left + corner, top + corner, lambda u: (-math.cos(u) ** power, -math.sin(u) ** power)),
    ]
    for cx, cy, direction in corners:
        for i in range(steps + 1):
            dx, dy = direction(math.pi / 2 * i / steps)
            points.append((cx + corner * dx, cy + corner * dy))
    return scaled(points)


def ecg_trace():
    """One heartbeat (P wave, QRS complex, T wave) between two flat lines."""
    base = 560
    points = [(176, base), (330, base)]
    points += [(x, base - 42 * math.sin(math.pi * (x - 330) / 70)) for x in range(332, 400, 4)]
    points += [(400, base), (430, base), (452, 598), (492, 268), (536, 700), (562, base), (604, base)]
    points += [(x, base - 64 * math.sin(math.pi * (x - 604) / 100)) for x in range(606, 704, 4)]
    points += [(704, base), (848, base)]
    return scaled(points)


def horizontal_ramp(start, end):
    """L image going from `start` (left) to `end` (right)."""
    ramp = Image.linear_gradient("L").rotate(90)  # 0 on the left, 255 on the right
    ramp = ramp.resize((SUPERSAMPLE, SUPERSAMPLE))
    return ramp.point(lambda v: int(start + (end - start) * v / 255))


def gradient(top_or_left, bottom_or_right, horizontal):
    first = Image.new("RGBA", (SUPERSAMPLE, SUPERSAMPLE), top_or_left + (255,))
    second = Image.new("RGBA", (SUPERSAMPLE, SUPERSAMPLE), bottom_or_right + (255,))
    mask = horizontal_ramp(0, 255) if horizontal else Image.linear_gradient("L").resize((SUPERSAMPLE, SUPERSAMPLE))
    return Image.composite(second, first, mask)


def stroke(points, width):
    """Anti-aliasing comes later from the reduction; round joins and caps."""
    mask = Image.new("L", (SUPERSAMPLE, SUPERSAMPLE), 0)
    draw = ImageDraw.Draw(mask)
    draw.line(points, fill=255, width=int(width * K), joint="curve")
    radius = width * K / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask


def with_alpha(image, alpha):
    image = image.copy()
    image.putalpha(alpha)
    return image


def draw_master(line_width, show_grid):
    canvas = Image.new("RGBA", (SUPERSAMPLE, SUPERSAMPLE), (0, 0, 0, 0))
    shape = Image.new("L", (SUPERSAMPLE, SUPERSAMPLE), 0)
    ImageDraw.Draw(shape).polygon(rounded_square(), fill=255)

    # Soft drop shadow below the tile.
    shadow = ImageChops.offset(shape, 0, int(14 * K)).filter(ImageFilter.GaussianBlur(22 * K))
    canvas.alpha_composite(with_alpha(Image.new("RGBA", canvas.size, (0, 0, 0, 255)), shadow.point(lambda v: v * 45 // 100)))

    # Monitor screen.
    canvas.alpha_composite(with_alpha(gradient(BACKGROUND_TOP, BACKGROUND_BOTTOM, horizontal=False), shape))

    if show_grid:
        grid = Image.new("L", canvas.size, 0)
        draw = ImageDraw.Draw(grid)
        for i, position in enumerate(range(64, 1024, 64)):
            value = 30 if i % 4 == 3 else 14
            draw.line(scaled([(position, 0), (position, 1024)]), fill=value, width=int(2 * K))
            draw.line(scaled([(0, position), (1024, position)]), fill=value, width=int(2 * K))
        grid = ImageChops.multiply(grid, shape)
        canvas.alpha_composite(with_alpha(Image.new("RGBA", canvas.size, (255, 255, 255, 255)), grid))

    # Faint highlight at the top of the glass.
    highlight = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(highlight).ellipse(scaled([(80, -260), (944, 330)]), fill=22)
    highlight = ImageChops.multiply(highlight.filter(ImageFilter.GaussianBlur(60 * K)), shape)
    canvas.alpha_composite(with_alpha(Image.new("RGBA", canvas.size, (255, 255, 255, 255)), highlight))

    # The trace fades towards the left, like on a monitor sweep.
    trace = ecg_trace()
    colours = gradient(TRACE_LEFT, TRACE_RIGHT, horizontal=True)
    fade = horizontal_ramp(70, 255)

    glow = stroke(trace, line_width * 2.4).filter(ImageFilter.GaussianBlur(26 * K))
    glow = ImageChops.multiply(ImageChops.multiply(glow, fade), shape).point(lambda v: v * 70 // 100)
    canvas.alpha_composite(with_alpha(colours, glow))
    canvas.alpha_composite(with_alpha(colours, ImageChops.multiply(stroke(trace, line_width), fade)))

    # Bright dot where the sweep is drawing now.
    x, y = trace[-1]
    halo = Image.new("L", canvas.size, 0)
    r = line_width * 1.9 * K
    ImageDraw.Draw(halo).ellipse((x - r, y - r, x + r, y + r), fill=255)
    halo = ImageChops.multiply(halo.filter(ImageFilter.GaussianBlur(20 * K)), shape)
    canvas.alpha_composite(with_alpha(Image.new("RGBA", canvas.size, TRACE_RIGHT + (255,)), halo))
    core = Image.new("L", canvas.size, 0)
    r = line_width * 0.85 * K
    ImageDraw.Draw(core).ellipse((x - r, y - r, x + r, y + r), fill=255)
    canvas.alpha_composite(with_alpha(Image.new("RGBA", canvas.size, (236, 255, 244, 255)), core))

    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def main():
    os.makedirs(OUTPUT, exist_ok=True)
    detailed = draw_master(line_width=30, show_grid=True)
    # Small sizes: thicker trace and no grid, so it stays legible.
    bold = draw_master(line_width=58, show_grid=False)

    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            master = bold if pixels <= 64 else detailed
            master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(os.path.join(OUTPUT, name), optimize=True)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})

    with open(os.path.join(OUTPUT, "Contents.json"), "w") as file:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, file, indent=2)
        file.write("\n")
    with open(os.path.join(os.path.dirname(OUTPUT), "Contents.json"), "w") as file:
        json.dump({"info": {"author": "xcode", "version": 1}}, file, indent=2)
        file.write("\n")


if __name__ == "__main__":
    main()
