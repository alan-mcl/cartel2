#!/usr/bin/env python3
"""Generate placeholder SVG and PNG assets for Cartel prototype."""

from __future__ import annotations

import random
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")


def write_png(path: Path, width: int, height: int, rgba_fn) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(rgba_fn(x, y, width, height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)
    print(f"wrote {path.relative_to(ROOT)}")


def stars_png(width: int, height: int, count: int, seed: int) -> None:
    rng = random.Random(seed)
    stars = [(rng.randint(0, width - 1), rng.randint(0, height - 1), rng.randint(120, 255)) for _ in range(count)]

    def rgba(x: int, y: int, w: int, h: int):
        for sx, sy, alpha in stars:
            if x == sx and y == sy:
                return bytes((220, 230, 255, alpha))
        return bytes((0, 0, 0, 0))

    return rgba


def planet_limb_png(width: int, height: int):
    cx, cy = width * 0.35, height * 0.55
    radius = min(width, height) * 0.72

    def rgba(x: int, y: int, w: int, h: int):
        dx = x - cx
        dy = y - cy
        dist = (dx * dx + dy * dy) ** 0.5
        if dist > radius:
            return bytes((0, 0, 0, 0))
        edge = max(0.0, 1.0 - (radius - dist) / 28.0)
        base = int(18 + edge * 24)
        alpha = int(min(255, max(0, (radius - dist + 18) * 6)))
        return bytes((base, base + 6, base + 14, alpha))

    return rgba


def main() -> None:
    write_text(
        ASSETS / "ships/chassis/flare_on_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="-32 -32 64 64">
  <polygon points="0,-24 16,18 0,10 -16,18" fill="#5ee0ff" stroke="#a8f0ff" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/chassis/pegasus_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="80" height="64" viewBox="-40 -32 80 64">
  <polygon points="0,-20 28,16 8,22 -8,22 -28,16" fill="#b8a878" stroke="#d8c8a0" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/fx/thrust.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="-16 -16 32 32">
  <polygon points="-8,8 0,20 8,8" fill="#ff8c33" opacity="0.85"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/habitat.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="260" height="160" viewBox="-130 -80 260 160">
  <polygon points="-110,-70 110,-70 130,0 110,70 -110,70 -130,0" fill="#d99e38" stroke="#f2c85a" stroke-width="4"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/jump_gate.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240" viewBox="-120 -120 240 240">
  <circle cx="0" cy="0" r="110" fill="none" stroke="#8ca6ff" stroke-width="8"/>
  <circle cx="0" cy="0" r="65" fill="none" stroke="#b8c8ff" stroke-width="4"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/beacon.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="64" viewBox="-24 -40 48 64">
  <rect x="-3" y="-10" width="6" height="30" fill="#59e6f2"/>
  <polygon points="-12,-28 12,-28 0,-8" fill="#59e6f2"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/wreck.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="-60 -40 120 80">
  <polygon points="-45,-20 50,-5 35,25 -30,30 -55,5" fill="#d95938" stroke="#8c2818" stroke-width="2"/>
  <polyline points="-20,-10 5,0 20,15" fill="none" stroke="#2a1208" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/debris.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="80" height="64" viewBox="-40 -32 80 64">
  <polygon points="-28,-18 24,-22 32,12 -8,28 -34,8" fill="#737880" stroke="#565b62" stroke-width="2"/>
</svg>""",
    )

    write_text(ASSETS / "ui/.gitkeep", "")

    write_png(ASSETS / "space/stars_far.png", 512, 512, stars_png(512, 512, 180, 90210))
    write_png(ASSETS / "space/stars_near.png", 512, 512, stars_png(512, 512, 320, 90211))
    write_png(ASSETS / "world/planet_limb.png", 512, 512, planet_limb_png(512, 512))


if __name__ == "__main__":
    main()
