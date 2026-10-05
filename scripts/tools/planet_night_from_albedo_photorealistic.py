#!/usr/bin/env python3
"""Build a photorealistic planet night-lights equirectangular PNG from a day albedo map.

The generator uses the albedo as a geographic mask and synthesizes several scales
of artificial lighting rather than drawing a small number of circular city blobs:

* tiny individual lamps / villages
* irregular urban street networks
* dense metropolitan cores
* long highways and coastal settlement corridors
* soft atmospheric bloom around brighter urban areas

The result is deliberately photographic-looking at planet scale: lights have
uneven brightness, gaps, clustering, branching roads, and a mixture of warm
and slightly cool light sources.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import random
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    print("ERROR: Pillow is required. Install with: pip install pillow", file=sys.stderr)
    sys.exit(1)


def _default_seed(path: Path) -> int:
    digest = hashlib.md5(str(path.resolve()).encode("utf-8")).hexdigest()
    return int(digest[:8], 16)


def _default_output_path(albedo_path: Path) -> Path:
    stem = albedo_path.stem
    if stem.endswith("_albedo"):
        stem = stem[: -len("_albedo")] + "_night"
    else:
        stem = stem + "_night"
    return albedo_path.with_name(stem + albedo_path.suffix)


def _is_near_black(r: int, g: int, b: int) -> bool:
    return r < 8 and g < 8 and b < 8


def _is_ocean(r: int, g: int, b: int) -> bool:
    if _is_near_black(r, g, b):
        return False
    return b > r * 1.15 and b > g * 1.05


def _is_land(r: int, g: int, b: int) -> bool:
    if _is_near_black(r, g, b):
        return False
    if _is_ocean(r, g, b):
        return False
    return True


def _latitude_weight(v: float) -> float:
    """Prefer temperate latitudes, but do not eliminate equatorial settlements."""
    return max(0.0, math.sin(v * math.pi)) ** 0.42


def _wrap_x(x: int, width: int) -> int:
    return x % width


def _land_mask(albedo: Image.Image) -> Image.Image:
    """Create a binary land mask from the day texture."""
    rgb = albedo.convert("RGB")
    px = rgb.load()
    width, height = rgb.size
    mask = Image.new("L", (width, height), 0)
    mp = mask.load()

    for y in range(height):
        for x in range(width):
            r, g, b = px[x, y]
            if _is_land(r, g, b):
                mp[x, y] = 255

    return mask


def _coast_distance(mask: Image.Image, max_distance: int) -> Image.Image:
    """Approximate distance to the coast using a cheap multi-scale dilation.

    This intentionally trades exact distance for speed. The output is a smooth
    0..255 map where high values mean 'closer to a coastline'.
    """
    # Downsample the mask so the operation stays inexpensive even for 8K maps.
    width, height = mask.size
    small_w = max(256, min(1024, width // 4))
    small_h = max(128, min(512, height // 4))
    small = mask.resize((small_w, small_h), Image.Resampling.BILINEAR)

    # Find ocean/land boundary by comparing the mask to a blurred version.
    blur = small.filter(ImageFilter.GaussianBlur(max(1.0, max_distance / 4.0)))
    # A boundary-strength map is sufficient for settlement bias.
    edge = ImageChops.difference(small, blur)
    edge = edge.point(lambda p: min(255, int(p * 3.0)))
    return edge.resize((width, height), Image.Resampling.BILINEAR)


def _candidate_is_land(mask_px, width: int, height: int, x: int, y: int) -> bool:
    if y < 0 or y >= height:
        return False
    return mask_px[_wrap_x(x, width), y] > 128


def _near_coast(coast_px, width: int, height: int, x: int, y: int) -> float:
    if y < 0 or y >= height:
        return 0.0
    return coast_px[_wrap_x(x, width), y] / 255.0


def _sample_land(
    mask_px,
    coast_px,
    width: int,
    height: int,
    rng: random.Random,
    density: float,
    max_attempts: int = 1000,
) -> tuple[int, int] | None:
    """Pick a plausible settlement location from the geographic mask."""
    for _ in range(max_attempts):
        x = rng.randrange(width)
        y = rng.randrange(height)

        lat_weight = _latitude_weight(y / max(height - 1, 1))

        # Population tends to concentrate near useful coastlines, while some
        # inland population remains. Keep this probabilistic rather than making
        # every city coastal.
        coast = _near_coast(coast_px, width, height, x, y)
        coastal_bias = 0.35 + 1.7 * coast
        probability = min(1.0, lat_weight * coastal_bias * (0.45 + 1.25 * density))

        if rng.random() > probability:
            continue
        if _candidate_is_land(mask_px, width, height, x, y):
            return x, y
    return None


def _line(
    draw: ImageDraw.ImageDraw,
    width: int,
    height: int,
    points: list[tuple[float, float]],
    fill,
    width_px: int,
) -> None:
    """Draw a polyline, duplicating across the equirectangular seam."""
    if len(points) < 2:
        return

    # Split at large horizontal jumps and draw each segment. This avoids a road
    # crossing the entire texture when it actually crosses the ±180° seam.
    segment = [points[0]]
    for p in points[1:]:
        if abs(p[0] - segment[-1][0]) > width * 0.45:
            if len(segment) > 1:
                draw.line(segment, fill=fill, width=max(1, width_px))
            segment = [p]
        else:
            segment.append(p)
    if len(segment) > 1:
        draw.line(segment, fill=fill, width=max(1, width_px))

    # Draw wrapped copies near the seam.
    shifted = []
    for x, y in points:
        shifted.append((x + width, y))
    draw.line(shifted, fill=fill, width=max(1, width_px))


def _draw_city(
    sharp: Image.Image,
    glow: Image.Image,
    width: int,
    height: int,
    cx: int,
    cy: int,
    radius: float,
    rng: random.Random,
    density: float,
) -> None:
    """Generate an irregular city entirely from individual point lights.

    No roads, strokes, circles, or multi-pixel lamps are drawn. Urban form comes
    from the spatial density and brightness distribution of individual pixels.
    """
    sharp_px = sharp.load()
    glow_px = glow.load()

    # Use a heavy-tailed density profile: a bright, dense central area with
    # increasingly sparse suburbs. Every actual light remains one pixel.
    area = math.pi * radius * radius
    lamp_count = max(12, int(area * (0.055 + density * 0.13)))

    for _ in range(lamp_count):
        # Gaussian placement gives naturally clustered neighborhoods rather
        # than a uniformly filled disk.
        x = int(round(cx + rng.gauss(0, radius * rng.uniform(0.28, 0.52))))
        y = int(round(cy + rng.gauss(0, radius * rng.uniform(0.22, 0.45))))

        x = _wrap_x(x, width)
        if y < 0 or y >= height:
            continue

        # Urban brightness follows a loose radial gradient, but with substantial
        # randomness so there are dark gaps and bright pockets.
        dist = math.hypot(x - cx, (y - cy) * 1.15) / max(radius, 1.0)
        if dist > 1.35:
            continue

        centrality = max(0.0, 1.0 - dist / 1.35)
        probability = 0.42 + 0.58 * centrality
        if rng.random() > probability:
            continue

        # Most lights are dim, a minority are bright.
        roll = rng.random()
        if roll < 0.015 * (1.0 + centrality * 2.0):
            lum = rng.randint(210, 255)
        elif roll < 0.18:
            lum = rng.randint(130, 210)
        else:
            lum = rng.randint(35, 145)

        # Warm urban illumination with occasional cooler/whiter LEDs.
        if rng.random() < 0.12:
            color = (rng.randint(195, 245), rng.randint(185, 230), rng.randint(145, 205), lum)
        else:
            color = (255, rng.randint(125, 205), rng.randint(35, 105), lum)

        # Hard constraint: one pixel, never an ellipse or stroke.
        sharp_px[x, y] = color

        # Extremely restrained bloom: not another visible "light blob", just a
        # subpixel-scale contribution that emerges when the planet is viewed
        # from a distance.
        if lum > 145:
            glow_px[x, y] = (255, rng.randint(65, 115), rng.randint(15, 45), lum // 4)


def _draw_settlement_network(
    sharp: Image.Image,
    glow: Image.Image,
    mask: Image.Image,
    coast: Image.Image,
    width: int,
    height: int,
    density: float,
    rng: random.Random,
) -> None:
    """Populate land with hierarchical clusters of point lights."""
    mask_px = mask.load()
    coast_px = coast.load()

    area_factor = (width * height) / 1_000_000.0

    # Primary cities are deliberately fewer than the individual lights they
    # contain. This gives recognisable concentrations without visible blobs.
    city_count = max(12, int((28 + 380 * density) * area_factor))
    cities: list[tuple[int, int, float]] = []

    for _ in range(city_count):
        point = _sample_land(mask_px, coast_px, width, height, rng, density)
        if point is None:
            continue

        cx, cy = point

        # Very broad city-size distribution. A handful of large metros coexist
        # with many small towns.
        size_roll = rng.random()
        if size_roll < 0.62:
            radius = rng.uniform(width * 0.0015, width * 0.0045)
        elif size_roll < 0.93:
            radius = rng.uniform(width * 0.0045, width * 0.010)
        else:
            radius = rng.uniform(width * 0.010, width * 0.022)

        if not _candidate_is_land(mask_px, width, height, cx, cy):
            continue

        _draw_city(sharp, glow, width, height, cx, cy, radius, rng, density)
        cities.append((cx, cy, radius))

    if not cities:
        return

    # Instead of drawing highways, place occasional individual lights along
    # plausible transport corridors. They are intentionally discontinuous.
    connections = max(1, int(len(cities) * (0.45 + density * 1.15)))

    sharp_px = sharp.load()
    glow_px = glow.load()

    for _ in range(connections):
        ax, ay, ar = rng.choice(cities)
        bx, by, br = rng.choice(cities)

        if ax == bx and ay == by:
            continue

        distance = math.hypot(bx - ax, by - ay)
        steps = max(4, int(distance / max(8, width * 0.004)))

        # Only a fraction of positions along the route become lights. This
        # suggests highways/settlement chains without ever drawing a line.
        for i in range(steps + 1):
            if rng.random() > (0.24 + density * 0.28):
                continue

            t = i / steps
            x = int(round(ax + (bx - ax) * t + rng.gauss(0, width * 0.0015)))
            y = int(round(ay + (by - ay) * t + rng.gauss(0, height * 0.0015)))
            x = _wrap_x(x, width)

            if y < 0 or y >= height:
                continue
            if not _candidate_is_land(mask_px, width, height, x, y):
                continue

            lum = rng.randint(30, 125)
            sharp_px[x, y] = (
                255,
                rng.randint(120, 195),
                rng.randint(30, 90),
                lum,
            )

            if lum > 100:
                glow_px[x, y] = (255, 85, 20, lum // 5)


def _scatter_villages(
    sharp: Image.Image,
    mask: Image.Image,
    width: int,
    height: int,
    density: float,
    rng: random.Random,
) -> None:
    """Add a broad background population of single-pixel lights."""
    px = mask.load()
    draw = sharp.load()

    # These are deliberately numerous but individually faint. At planet scale
    # they merge into realistic settlement patterns without becoming blobs.
    count = int((width * height) / 1500 * density)

    for _ in range(count):
        x = rng.randrange(width)
        y = rng.randrange(height)

        if not _candidate_is_land(px, width, height, x, y):
            continue

        if rng.random() > _latitude_weight(y / max(height - 1, 1)):
            continue

        # Small local clusters occur naturally, but every light is one pixel.
        if rng.random() < 0.28:
            cluster = rng.randint(3, 11)
            for _ in range(cluster):
                xx = _wrap_x(x + rng.randint(-4, 4), width)
                yy = y + rng.randint(-3, 3)
                if yy < 0 or yy >= height:
                    continue
                if not _candidate_is_land(px, width, height, xx, yy):
                    continue
                lum = rng.randint(25, 105)
                draw[xx, yy] = (
                    255,
                    rng.randint(120, 190),
                    rng.randint(25, 80),
                    lum,
                )
        else:
            lum = rng.randint(20, 95)
            draw[x, y] = (
                255,
                rng.randint(115, 185),
                rng.randint(20, 75),
                lum,
            )


def build_night_lights(
    albedo: Image.Image,
    density: float,
    seed: int,
) -> Image.Image:
    if albedo.mode != "RGB":
        albedo = albedo.convert("RGB")

    width, height = albedo.size
    if width != height * 2:
        print(
            f"warning: albedo is {width}x{height} (expected 2:1 equirectangular); "
            "writing output at the same size as input.",
            file=sys.stderr,
        )

    if density <= 0.0:
        return Image.new("RGB", (width, height), (0, 0, 0))

    rng = random.Random(seed)

    # Geographic masks.
    mask = _land_mask(albedo)
    coast = _coast_distance(mask, max(8, int(width * 0.004)))

    # Work in RGBA so we can build natural-looking light layers independently.
    sharp = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    _draw_settlement_network(
        sharp, glow, mask, coast, width, height, density, rng
    )
    _scatter_villages(sharp, mask, width, height, density, rng)

    # Multiple bloom scales make bright cities read as luminous atmospheric
    # sources rather than painted orange circles.
    glow_small = glow.filter(
        ImageFilter.GaussianBlur(max(0.35, width * 0.00035))
    )
    glow_large = glow.filter(
        ImageFilter.GaussianBlur(max(0.6, width * 0.0012))
    )

    # Keep the hard light detail crisp, then composite increasingly broad bloom.
    result = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    result = Image.alpha_composite(result, glow_large)
    result = Image.alpha_composite(result, glow_small)
    result = Image.alpha_composite(result, sharp)

    # Enforce the geographic mask at the end. A tiny edge feather avoids
    # unnaturally clipped pixels at coastlines.
    mask_soft = mask.filter(ImageFilter.GaussianBlur(max(0.4, width * 0.00015)))
    black = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    result = Image.composite(result, black, mask_soft)

    # Final photographic color treatment: compress highlights and slightly
    # desaturate the very brightest lamps toward warm white.
    rgb = result.convert("RGB")
    px = rgb.load()
    for y in range(height):
        for x in range(width):
            r, g, b = px[x, y]
            if r == 0 and g == 0 and b == 0:
                continue
            # Warm sodium/LED mixture with a small cool component.
            peak = max(r, g, b)
            if peak > 210:
                lift = min(35, peak - 210)
                g = min(255, g + lift // 3)
                b = min(255, b + lift // 5)
            px[x, y] = (r, g, b)

    return rgb


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a photorealistic planet night-lights PNG from an equirectangular day albedo."
    )
    parser.add_argument(
        "albedo",
        type=Path,
        help="Path to the day albedo PNG (same UV layout as in-game planet.albedo)",
    )
    parser.add_argument(
        "--density",
        type=float,
        required=True,
        help="Population density 0.0–1.0 (0 = black night map, 1 = heavily settled)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output PNG path (default: <sector>_night.png beside albedo)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="RNG seed (default: derived from albedo path)",
    )
    args = parser.parse_args()

    density = max(0.0, min(1.0, args.density))
    albedo_path = args.albedo
    if not albedo_path.is_file():
        print(f"ERROR: albedo not found: {albedo_path}", file=sys.stderr)
        return 1

    output_path = args.output if args.output is not None else _default_output_path(albedo_path)
    seed = args.seed if args.seed is not None else _default_seed(albedo_path)

    albedo = Image.open(albedo_path)
    night = build_night_lights(albedo, density, seed)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    night.save(output_path, format="PNG")
    print(f"wrote {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
