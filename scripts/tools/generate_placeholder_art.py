#!/usr/bin/env python3
"""Generate placeholder SVG and PNG assets for Cartel prototype."""

from __future__ import annotations

import hashlib
import math
import os
import random
import struct
import subprocess
import sys
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


SECTOR_PLANET_TINTS: dict[str, str] = {
    "proxima": "#ffffff",
    "tycho": "#dd8844",
    "bela": "#88bbdd",
    "irasia": "#c8d4b8",
    "tokirev": "#a8c0d8",
    "fennet": "#90c090",
    "fortuna": "#e8d8a8",
    "new_carthage": "#70c8c8",
    "horizon": "#b8d0a8",
    "titania": "#c8d8f0",
    "pelagos": "#d4a060",
}


def _hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.lstrip("#")
    if len(value) != 6:
        return (255, 255, 255)
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def _planet_ocean_land(tint_hex: str) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    red, green, blue = _hex_to_rgb(tint_hex)
    if tint_hex.lower() in ("#ffffff", "#fff"):
        ocean = (18, 36, 88)
        land = (42, 78, 52)
        return ocean, land
    ocean = (max(8, int(red * 0.22)), max(8, int(green * 0.28)), max(12, int(blue * 0.38)))
    land = (max(8, int(red * 0.55)), max(8, int(green * 0.62)), max(8, int(blue * 0.45)))
    return ocean, land


def planet_albedo_equirect_png(width: int, height: int, tint_hex: str, seed: int):
    ocean, land = _planet_ocean_land(tint_hex)
    blob_centers: list[tuple[float, float]] = []
    for index in range(5):
        cx = math.sin(seed * 0.013 + index * 2.1) * 0.5 + 0.5
        cy = math.cos(seed * 0.017 + index * 1.7) * 0.3 + 0.35
        blob_centers.append((cx, cy))

    def land_strength(u: float, v: float) -> float:
        wave_a = math.sin(u * 6.28318 * 3.0 + math.sin(v * 6.28318 * 2.0) * 1.7) * 0.5 + 0.5
        wave_b = math.cos(v * 6.28318 * 4.0 + math.cos(u * 6.28318 * 2.5) * 1.3) * 0.5 + 0.5
        blob = 0.0
        for cx, cy in blob_centers:
            dist = ((u - cx) ** 2 + (v - cy) ** 2) ** 0.5
            blob = max(blob, max(0.0, 1.0 - dist * 6.0))
        mix_val = wave_a * 0.45 + wave_b * 0.35 + blob * 0.35
        if mix_val < 0.42:
            return 0.0
        if mix_val > 0.58:
            return 1.0
        return (mix_val - 0.42) / 0.16

    def rgba(x: int, y: int, w: int, h: int):
        u = x / max(w - 1, 1)
        v = y / max(h - 1, 1)
        strength = land_strength(u, v)
        red = int(ocean[0] * (1.0 - strength) + land[0] * strength)
        green = int(ocean[1] * (1.0 - strength) + land[1] * strength)
        blue = int(ocean[2] * (1.0 - strength) + land[2] * strength)
        return bytes((red, green, blue, 255))

    return rgba


def planet_night_lights_equirect_png(width: int, height: int, seed: int):
    rng = random.Random(seed + 991)
    cities: list[tuple[float, float, int]] = []
    for _ in range(48):
        cities.append((rng.uniform(0.0, 1.0), rng.uniform(0.15, 0.85), rng.randint(140, 255)))

    def rgba(x: int, y: int, w: int, h: int):
        u = x / max(w - 1, 1)
        v = y / max(h - 1, 1)
        glow = 0
        for cu, cv, intensity in cities:
            dist = ((u - cu) ** 2 + (v - cv) ** 2) ** 0.5
            if dist < 0.018:
                glow = max(glow, intensity)
            elif dist < 0.045:
                falloff = 1.0 - (dist - 0.018) / 0.027
                glow = max(glow, int(intensity * falloff * 0.35))
        if glow <= 0:
            return bytes((0, 0, 0, 255))
        return bytes((min(255, glow + 40), min(255, int(glow * 0.75)), min(255, int(glow * 0.35)), 255))

    return rgba


def write_png_if_missing(path: Path, width: int, height: int, rgba_fn) -> None:
    if path.is_file():
        print(f"skip existing {path.relative_to(ROOT)}")
        return
    write_png(path, width, height, rgba_fn)


def generate_planet_texture_placeholders() -> None:
    width, height = 1024, 512
    planets_dir = ASSETS / "world/planets"
    planets_dir.mkdir(parents=True, exist_ok=True)
    for sector_id, tint_hex in SECTOR_PLANET_TINTS.items():
        seed = int(hashlib.md5(sector_id.encode("utf-8")).hexdigest()[:8], 16)
        albedo_path = planets_dir / f"{sector_id}_albedo.png"
        night_path = planets_dir / f"{sector_id}_night.png"
        write_png_if_missing(
            albedo_path,
            width,
            height,
            planet_albedo_equirect_png(width, height, tint_hex, seed),
        )
        write_png_if_missing(
            night_path,
            width,
            height,
            planet_night_lights_equirect_png(width, height, seed),
        )


def planet_disc_png(width: int, height: int):
    cx, cy = width / 2, height / 2
    radius = min(width, height) * 0.46

    def rgba(x: int, y: int, w: int, h: int):
        dx = x - cx
        dy = y - cy
        dist = (dx * dx + dy * dy) ** 0.5
        if dist > radius:
            return bytes((0, 0, 0, 0))
        edge = max(0.0, 1.0 - (radius - dist) / 36.0)
        red = int(24 + edge * 28)
        green = int(52 + edge * 60)
        blue = int(110 + edge * 100)
        alpha = int(min(255, max(0, (radius - dist + 24) * 5)))
        return bytes((red, green, blue, alpha))

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
        ASSETS / "ships/chassis/krypton_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="-36 -36 72 72">
  <ellipse cx="0" cy="0" rx="28" ry="12" fill="#c8e878" stroke="#e8f8a8" stroke-width="2"/>
  <ellipse cx="0" cy="0" rx="10" ry="10" fill="#98b858" stroke="#e8f8a8" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/chassis/wolff_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="88" height="64" viewBox="-44 -32 88 64">
  <rect x="-32" y="-18" width="64" height="36" rx="4" fill="#8898a8" stroke="#b8c8d8" stroke-width="2"/>
  <rect x="-12" y="-26" width="24" height="10" fill="#687888" stroke="#b8c8d8" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/chassis/dragon_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="96" height="48" viewBox="-48 -24 96 48">
  <polygon points="40,-8 40,8 -36,14 -36,-14" fill="#ffd060" stroke="#ffe8a0" stroke-width="2"/>
  <polygon points="-36,-10 -36,10 -44,0" fill="#c8a040" stroke="#ffe8a0" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/chassis/juno_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="72" height="56" viewBox="-36 -28 72 56">
  <polygon points="0,-22 30,12 0,18 -30,12" fill="#a8b8d0" stroke="#d0d8e8" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/chassis/silhouette_chassis.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40" viewBox="-40 -20 80 40">
  <polygon points="0,-16 34,0 0,12 -34,0" fill="#d87888" stroke="#f0a8b8" stroke-width="2"/>
  <line x1="-20" y1="0" x2="20" y2="0" stroke="#f0a8b8" stroke-width="2"/>
</svg>""",
    )

    write_text(
        ASSETS / "ships/fx/thrust.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="-16 -16 32 32">
  <polygon points="-8,8 0,20 8,8" fill="#ff8c33" opacity="0.85"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/habitat_proxima.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="280" height="180" viewBox="-140 -90 280 180">
  <polygon points="-120,-75 120,-75 145,0 120,75 -120,75 -145,0" fill="#d99e38" stroke="#f2c85a" stroke-width="5"/>
  <rect x="-35" y="-15" width="70" height="30" rx="4" fill="#f2c85a" opacity="0.45"/>
</svg>""",
    )

    write_text(
        ASSETS / "world/habitat_bela.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="280" height="180" viewBox="-140 -90 280 180">
  <ellipse cx="0" cy="0" rx="130" ry="70" fill="#5a9ec8" stroke="#9fd4f5" stroke-width="5"/>
  <ellipse cx="0" cy="0" rx="95" ry="48" fill="none" stroke="#d8f0ff" stroke-width="3"/>
</svg>""",
    )

    orbitals = {
        "torus.svg": """<svg xmlns="http://www.w3.org/2000/svg" width="140" height="140" viewBox="-70 -70 140 140">
  <ellipse cx="0" cy="0" rx="55" ry="22" fill="none" stroke="#8aa0b8" stroke-width="6"/>
  <ellipse cx="0" cy="0" rx="22" ry="55" fill="none" stroke="#8aa0b8" stroke-width="6"/>
</svg>""",
        "yard.svg": """<svg xmlns="http://www.w3.org/2000/svg" width="160" height="100" viewBox="-80 -50 160 100">
  <rect x="-70" y="-20" width="140" height="40" fill="#6a7580" stroke="#9aa5b0" stroke-width="3"/>
  <rect x="-50" y="-45" width="30" height="25" fill="#505860" stroke="#9aa5b0" stroke-width="2"/>
  <rect x="20" y="-45" width="30" height="25" fill="#505860" stroke="#9aa5b0" stroke-width="2"/>
</svg>""",
        "tank_farm.svg": """<svg xmlns="http://www.w3.org/2000/svg" width="150" height="110" viewBox="-75 -55 150 110">
  <ellipse cx="-35" cy="10" rx="22" ry="35" fill="#607080" stroke="#90a8b8" stroke-width="3"/>
  <ellipse cx="35" cy="10" rx="22" ry="35" fill="#607080" stroke="#90a8b8" stroke-width="3"/>
  <rect x="-57" y="-25" width="114" height="8" fill="#90a8b8"/>
</svg>""",
        "array.svg": """<svg xmlns="http://www.w3.org/2000/svg" width="130" height="130" viewBox="-65 -65 130 130">
  <line x1="-50" y1="0" x2="50" y2="0" stroke="#7a90a8" stroke-width="4"/>
  <line x1="0" y1="-50" x2="0" y2="50" stroke="#7a90a8" stroke-width="4"/>
  <circle cx="0" cy="0" r="18" fill="#506070" stroke="#9ab0c8" stroke-width="3"/>
</svg>""",
        "tower.svg": """<svg xmlns="http://www.w3.org/2000/svg" width="90" height="160" viewBox="-45 -80 90 160">
  <rect x="-8" y="-60" width="16" height="120" fill="#687888" stroke="#98a8b8" stroke-width="3"/>
  <polygon points="-20,-70 20,-70 0,-55" fill="#98a8b8"/>
  <line x1="-25" y1="-40" x2="25" y2="-40" stroke="#98a8b8" stroke-width="2"/>
  <line x1="-18" y1="-10" x2="18" y2="-10" stroke="#98a8b8" stroke-width="2"/>
</svg>""",
        "platform.svg": """<svg xmlns="http://www.w3.org/2000/svg" width="170" height="90" viewBox="-85 -45 170 90">
  <polygon points="-75,20 75,20 60,-15 -60,-15" fill="#5a6878" stroke="#8a98a8" stroke-width="3"/>
  <rect x="-20" y="-35" width="40" height="20" fill="#708090" stroke="#8a98a8" stroke-width="2"/>
</svg>""",
    }
    for name, svg in orbitals.items():
        write_text(ASSETS / f"world/orbitals/{name}", svg)

    write_text(
        ASSETS / "world/jump_gate.svg",
        """<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240" viewBox="-120 -120 240 240">
  <circle cx="0" cy="0" r="110" fill="none" stroke="#8ca6ff" stroke-width="8"/>
  <circle cx="0" cy="0" r="65" fill="none" stroke="#b8c8ff" stroke-width="4"/>
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
    write_png(ASSETS / "world/planet.png", 512, 512, planet_disc_png(512, 512))
    generate_planet_texture_placeholders()

    _run_godot_import()


def _find_godot_binary() -> Path | None:
    env_path = os.environ.get("GODOT")
    if env_path:
        candidate = Path(env_path).expanduser()
        if candidate.is_file():
            return candidate

    for candidate in (
        Path.home() / "opt/Godot_v4.7.2-stable_linux.x86_64",
        Path("/usr/bin/godot"),
        Path("/usr/local/bin/godot"),
    ):
        if candidate.is_file():
            return candidate
    return None


def _run_godot_import() -> None:
    godot = _find_godot_binary()
    if godot is None:
        print(
            "warning: Godot binary not found; run `godot --path . --import --headless --quit` "
            "so new SVG/PNG assets get .import sidecars.",
            file=sys.stderr,
        )
        return

    print(f"running Godot import via {godot}")
    result = subprocess.run(
        [str(godot), "--path", str(ROOT), "--import", "--headless", "--quit"],
        check=False,
    )
    if result.returncode != 0:
        print(f"warning: Godot import exited with code {result.returncode}", file=sys.stderr)


if __name__ == "__main__":
    main()
