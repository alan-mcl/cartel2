#!/usr/bin/env python3
"""Write skip-if-present placeholder PNGs for module category icons and chassis UI headers."""

from __future__ import annotations

import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"

MODULE_CATEGORIES = [
    "propulsion",
    "power",
    "computer",
    "life_support",
    "sensor",
    "navigation",
    "hyperdrive",
    "weapon",
    "armour",
    "cargo",
    "fuel",
    "ammunition",
    "shield",
    "point_defence",
    "cyber_defence",
    "transponder",
]

CHASSIS_IDS = [
    "flare_on_chassis",
    "pegasus_chassis",
    "krypton_chassis",
    "wolff_chassis",
    "dragon_chassis",
    "juno_chassis",
    "silhouette_chassis",
]

# Muted palette per category (RGBA) for placeholder icons.
CATEGORY_TINTS: dict[str, tuple[int, int, int]] = {
    "propulsion": (255, 140, 80),
    "power": (255, 210, 80),
    "computer": (100, 180, 255),
    "life_support": (120, 220, 160),
    "sensor": (180, 140, 255),
    "navigation": (140, 200, 220),
    "hyperdrive": (220, 120, 255),
    "weapon": (255, 100, 100),
    "armour": (160, 170, 190),
    "cargo": (200, 160, 120),
    "fuel": (255, 180, 60),
    "ammunition": (190, 190, 130),
    "shield": (100, 220, 255),
    "point_defence": (255, 160, 200),
    "cyber_defence": (140, 255, 180),
    "transponder": (180, 180, 255),
}

CHASSIS_TINTS: dict[str, tuple[int, int, int]] = {
    "flare_on_chassis": (94, 224, 255),
    "pegasus_chassis": (184, 168, 120),
    "krypton_chassis": (200, 232, 120),
    "wolff_chassis": (136, 152, 168),
    "dragon_chassis": (255, 208, 96),
    "juno_chassis": (168, 184, 208),
    "silhouette_chassis": (216, 120, 136),
}


def write_png(path: Path, width: int, height: int, rgba_fn) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(rgba_fn(x, y, width, height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)
    print(f"wrote {path.relative_to(ROOT)}")


def _rounded_icon_rgba(
    x: int, y: int, w: int, h: int, rgb: tuple[int, int, int]
) -> bytes:
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    dx = (x - cx) / max(cx, 1.0)
    dy = (y - cy) / max(cy, 1.0)
    dist = (dx * dx + dy * dy) ** 0.5
    if dist > 0.92:
        return bytes((0, 0, 0, 0))
    edge = max(0.0, min(1.0, (0.92 - dist) / 0.08))
    alpha = int(220 * edge + 20)
    return bytes((rgb[0], rgb[1], rgb[2], alpha))


def _header_rgba(
    x: int, y: int, w: int, h: int, rgb: tuple[int, int, int]
) -> bytes:
    # Dark vignette with tinted centre band (16:9 UI header placeholder).
    nx = x / max(w - 1, 1)
    ny = y / max(h - 1, 1)
    band = max(0.0, 1.0 - abs(ny - 0.45) * 2.2)
    vignette = 0.35 + 0.65 * (1.0 - ((nx - 0.5) ** 2 + (ny - 0.5) ** 2) ** 0.5 * 1.4)
    vignette = max(0.15, min(1.0, vignette))
    mix = 0.25 + 0.75 * band
    r = int(rgb[0] * mix * vignette)
    g = int(rgb[1] * mix * vignette)
    b = int(rgb[2] * mix * vignette)
    return bytes((r, g, b, 255))


def write_module_icons() -> None:
    for category in MODULE_CATEGORIES:
        path = ASSETS / "ui" / "modules" / f"{category}.png"
        if path.is_file():
            continue
        tint = CATEGORY_TINTS.get(category, (160, 160, 180))

        def rgba_fn(x, y, w, h, tint=tint):
            return _rounded_icon_rgba(x, y, w, h, tint)

        write_png(path, 64, 64, rgba_fn)


def write_chassis_headers() -> None:
    for chassis_id in CHASSIS_IDS:
        path = ASSETS / "ui" / "ships" / f"{chassis_id}.png"
        if path.is_file():
            continue
        tint = CHASSIS_TINTS.get(chassis_id, (140, 150, 170))

        def rgba_fn(x, y, w, h, tint=tint):
            return _header_rgba(x, y, w, h, tint)

        write_png(path, 640, 360, rgba_fn)


def run_godot_import() -> None:
    godot = Path.home() / "opt" / "Godot_v4.7.2-stable_linux.x86_64"
    if not godot.is_file():
        godot_env = __import__("os").environ.get("GODOT", "")
        if godot_env:
            godot = Path(godot_env)
    if not godot.is_file():
        print("skip Godot import (GODOT not found)")
        return
    subprocess.run(
        [str(godot), "--path", str(ROOT), "--headless", "--import", "--quit"],
        check=False,
        cwd=ROOT,
    )


def main() -> int:
    write_module_icons()
    write_chassis_headers()
    run_godot_import()
    return 0


if __name__ == "__main__":
    sys.exit(main())
