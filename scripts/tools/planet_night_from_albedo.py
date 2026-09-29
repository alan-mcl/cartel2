#!/usr/bin/env python3
"""Build a planet night-lights equirect PNG from a day albedo map."""

from __future__ import annotations

import argparse
import hashlib
import math
import random
import sys
from pathlib import Path

try:
    from PIL import Image
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
    return max(0.0, math.sin(v * math.pi)) ** 0.65


def _warm_rgb(glow: int) -> tuple[int, int, int]:
    return (
        min(255, glow + 40),
        min(255, int(glow * 0.75)),
        min(255, int(glow * 0.35)),
    )


def _stamp_city(
    glow: list[int],
    width: int,
    height: int,
    cx: int,
    cy: int,
    intensity: int,
    core_px: int,
    halo_px: int,
) -> None:
    for dy in range(-halo_px, halo_px + 1):
        for dx in range(-halo_px, halo_px + 1):
            dist = math.hypot(dx, dy)
            if dist > halo_px:
                continue
            if dist <= core_px:
                value = intensity
            else:
                falloff = 1.0 - (dist - core_px) / max(halo_px - core_px, 1)
                value = int(intensity * falloff * 0.4)
            px = cy + dy
            py_x = cx + dx
            if px < 0 or px >= height or py_x < 0 or py_x >= width:
                continue
            index = py_x + px * width
            if value > glow[index]:
                glow[index] = value


def _pick_land_pixel(
    pixels,
    width: int,
    height: int,
    rng: random.Random,
    max_attempts: int = 800,
) -> tuple[int, int] | None:
    for _ in range(max_attempts):
        x = rng.randint(0, width - 1)
        y = rng.randint(0, height - 1)
        v = y / max(height - 1, 1)
        if rng.random() > _latitude_weight(v):
            continue
        r, g, b = pixels[x, y][:3]
        if _is_land(r, g, b):
            return x, y
    return None


def _pixel_land(pixels, width: int, height: int, x: int, y: int) -> bool:
    if x < 0 or x >= width or y < 0 or y >= height:
        return False
    r, g, b = pixels[x, y][:3]
    return _is_land(r, g, b)


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

    pixels = albedo.load()
    glow = [0] * (width * height)
    core_px = max(2, int(0.009 * width))
    halo_px = max(core_px + 1, int(0.024 * width))

    if density <= 0.0:
        return Image.new("RGB", (width, height), (0, 0, 0))

    rng = random.Random(seed)
    city_count = max(1, int(density * (width * height) / 12000.0))
    placed: list[tuple[int, int]] = []

    for index in range(city_count):
        point: tuple[int, int] | None = None
        if placed and rng.random() < 0.35:
            base_x, base_y = rng.choice(placed)
            for _ in range(40):
                ox = base_x + rng.randint(-halo_px * 3, halo_px * 3)
                oy = base_y + rng.randint(-halo_px * 3, halo_px * 3)
                if _pixel_land(pixels, width, height, ox, oy):
                    point = (ox, oy)
                    break
        if point is None:
            point = _pick_land_pixel(pixels, width, height, rng)
        if point is None:
            continue
        cx, cy = point
        placed.append(point)
        intensity = rng.randint(100, 255)
        _stamp_city(glow, width, height, cx, cy, intensity, core_px, halo_px)

    out = Image.new("RGB", (width, height))
    out_pixels = out.load()
    for y in range(height):
        for x in range(width):
            value = glow[x + y * width]
            if value <= 0:
                out_pixels[x, y] = (0, 0, 0)
            else:
                out_pixels[x, y] = _warm_rgb(value)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a planet night-lights PNG from an equirectangular day albedo."
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
