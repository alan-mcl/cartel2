#!/usr/bin/env python3
"""Generate distinct 16:9 location banner PNGs referenced by habitats and buildings catalogs."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"
LOCATIONS = ROOT / "assets" / "ui" / "locations"
WIDTH = 640
HEIGHT = 360

# Preserve authored Proxima banners; copy legacy filenames where ids changed.
COPY_SOURCES: dict[str, str] = {
    "proxima_habitat_terminal.png": "proxima_terminal.png",
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
    compressed = zlib.compress(bytes(raw), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(png)


def _seed(name: str) -> int:
    digest = hashlib.sha256(name.encode("utf-8")).digest()
    return int.from_bytes(digest[:4], "big")


def _theme(record_id: str) -> tuple[tuple[int, int, int], tuple[int, int, int], tuple[int, int, int]]:
    """Return sky, accent, and ground RGB from a stable hash."""
    seed = _seed(record_id)
    rng = seed

    def nxt() -> float:
        nonlocal rng
        rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
        return (rng % 1000) / 1000.0

    sky = (int(20 + nxt() * 80), int(30 + nxt() * 90), int(60 + nxt() * 120))
    accent = (int(80 + nxt() * 120), int(90 + nxt() * 110), int(100 + nxt() * 120))
    ground = (int(10 + nxt() * 40), int(15 + nxt() * 45), int(20 + nxt() * 50))
    return sky, accent, ground


def _kind_tint(record_id: str) -> float:
    if record_id.endswith("_shipyard"):
        return 0.35
    if record_id.endswith("_exchange"):
        return 0.55
    if "terminal" in record_id:
        return 0.45
    if record_id.endswith("_habitat") or "orbital_habitat" in record_id:
        return 0.25
    return 0.4


def render_banner(record_id: str, path: Path) -> None:
    sky, accent, ground = _theme(record_id)
    kind_bias = _kind_tint(record_id)
    seed = _seed(record_id + ":scene")

    def rgba(x: int, y: int, w: int, h: int) -> bytes:
        t = y / max(h - 1, 1)
        horizon = 0.58 + 0.06 * math.sin((x / w) * math.pi * 2.0)
        r = int(sky[0] * (1 - t) + ground[0] * t)
        g = int(sky[1] * (1 - t) + ground[1] * t)
        b = int(sky[2] * (1 - t) + ground[2] * t)

        if t > horizon:
            fog = (t - horizon) / max(1.0 - horizon, 0.01)
            r = int(r * (1 - 0.35 * fog) + accent[0] * 0.35 * fog)
            g = int(g * (1 - 0.35 * fog) + accent[1] * 0.35 * fog)
            b = int(b * (1 - 0.35 * fog) + accent[2] * 0.35 * fog)

        # Planet limb
        cx, cy, rad = w * 0.72, h * 0.78, h * 0.42
        dx, dy = x - cx, y - cy
        dist = math.sqrt(dx * dx + dy * dy)
        if dist < rad:
            limb = 1.0 - dist / rad
            pr = int(accent[0] * 0.4 + 40 * limb)
            pg = int(accent[1] * 0.35 + 50 * limb)
            pb = int(accent[2] * 0.45 + 70 * limb)
            r = int(r * 0.35 + pr * 0.65)
            g = int(g * 0.35 + pg * 0.65)
            b = int(b * 0.35 + pb * 0.65)

        # Station band (habitat / terminal / yard silhouettes)
        band_y = int(h * (0.28 + kind_bias * 0.12))
        band_h = int(h * (0.08 + kind_bias * 0.06))
        if band_y <= y <= band_y + band_h:
            pulse = 0.65 + 0.35 * math.sin(x * 0.02 + seed * 0.001)
            r = int(r * 0.2 + accent[0] * pulse)
            g = int(g * 0.2 + accent[1] * pulse)
            b = int(b * 0.2 + accent[2] * pulse)

        # Spark/weld points for shipyards
        if record_id.endswith("_shipyard"):
            for i in range(6):
                sx = (seed // (i + 3)) % w
                sy = band_y + (seed // (i + 11)) % max(band_h, 1)
                if abs(x - sx) < 3 and abs(y - sy) < 3:
                    r, g, b = 255, 180, 80

        # Twin sun for Concordia
        if record_id.startswith("concordia"):
            for ox in (w * 0.18, w * 0.28):
                sdx, sdy = x - ox, y - h * 0.18
                if sdx * sdx + sdy * sdy < (h * 0.04) ** 2:
                    r, g, b = 255, 240, 200

        return bytes((max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), 255))

    write_png(path, WIDTH, HEIGHT, rgba)
    print(f"wrote {path.relative_to(ROOT)}")


def art_path_to_file(art: str) -> Path | None:
    if not art.startswith("res://assets/ui/locations/"):
        return None
    name = art.removeprefix("res://assets/ui/locations/")
    return LOCATIONS / name


def collect_art_paths() -> set[str]:
    paths: set[str] = set()
    for filename in ("habitats.json", "buildings.json"):
        entries = json.loads((CATALOG / filename).read_text(encoding="utf-8"))
        for entry in entries:
            art = str(entry.get("art", ""))
            if art:
                paths.add(art)
    return paths


def main() -> int:
    LOCATIONS.mkdir(parents=True, exist_ok=True)

    for dest_name, src_name in COPY_SOURCES.items():
        dest = LOCATIONS / dest_name
        src = LOCATIONS / src_name
        if src.is_file() and not dest.is_file():
            shutil.copy2(src, dest)
            print(f"copied {src_name} -> {dest_name}")

    preserve = {
        "proxima_habitat.png",
        "proxima_shipyard.png",
        "proxima_exchange.png",
        "davidsons.png",
        "skyedge.png",
        "concord_scouts.png",
    }

    for art in sorted(collect_art_paths()):
        path = art_path_to_file(art)
        if path is None:
            continue
        if path.name in preserve and path.is_file():
            continue
        if path.is_file():
            continue
        record_id = path.stem
        render_banner(record_id, path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
