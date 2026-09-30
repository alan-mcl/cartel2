#!/usr/bin/env python3
"""Generate data/catalog/corporate_presence.json from corporations.json and lore anchors."""

from __future__ import annotations

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"

SECTORS = [
    "proxima",
    "tycho",
    "bela",
    "irasia",
    "tokirev",
    "fennet",
    "fortuna",
    "new_carthage",
    "horizon",
    "titania",
    "pelagos",
]

# Extra weight per sector for selected corporation ids (added on top of floor + jitter).
SECTOR_ANCHORS: dict[str, dict[str, float]] = {
    "proxima": {
        "creus": 8.0,
        "grc": 7.0,
        "mercury_communications": 5.0,
        "meridian": 4.0,
        "pararamcovidia": 4.0,
    },
    "fortuna": {
        "creus": 9.0,
        "grc": 8.0,
        "octagon": 5.0,
        "house_of_roth": 4.0,
        "karaquazen": 3.0,
    },
    "tycho": {
        "atlas_concern": 7.0,
        "general_industrial": 6.0,
        "terra_nova": 5.0,
        "oklahoma_combine": 4.0,
        "deepspace": 6.0,
    },
    "tokirev": {
        "atlas_concern": 8.0,
        "general_industrial": 7.0,
        "four_rivers_zaibatsu": 5.0,
        "oklahoma_combine": 4.0,
    },
    "bela": {
        "karaquazen": 10.0,
        "liveworlds": 5.0,
        "carthage_mercantile": 3.0,
        "universal_house": 3.0,
    },
    "titania": {
        "karaquazen": 4.0,
        "liveworlds": 6.0,
        "deepspace": 5.0,
        "evergreen": 3.0,
    },
    "new_carthage": {
        "carthage_mercantile": 9.0,
        "guangzhou_mercantile": 6.0,
        "crown_and_anchor": 5.0,
        "meridian": 4.0,
    },
    "irasia": {
        "guangzhou_mercantile": 6.0,
        "meridian": 5.0,
        "chettiar": 4.0,
        "orion_spur": 4.0,
    },
    "fennet": {
        "pacific_triad": 5.0,
        "deepspace": 8.0,
        "orion_spur": 4.0,
        "tukey": 3.0,
    },
    "horizon": {
        "microdonald": 5.0,
        "monday": 4.0,
        "mercury_communications": 4.0,
        "evergreen": 3.0,
    },
    "pelagos": {
        "deepspace": 7.0,
        "atlas_concern": 4.0,
        "biogenesis": 3.0,
        "greenfields": 3.0,
    },
}

FLOOR = 0.15
RNG_SEED = 264601


def _normalize(raw: dict[str, float]) -> dict[str, float]:
    total = sum(raw.values())
    if total <= 0:
        raise ValueError("empty weights")
    scaled = {k: 100.0 * v / total for k, v in raw.items()}
    # Round to two decimals and fix drift on largest bucket.
    rounded = {k: round(v, 2) for k, v in scaled.items()}
    drift = round(100.0 - sum(rounded.values()), 2)
    if abs(drift) >= 0.01:
        top = max(rounded, key=rounded.get)
        rounded[top] = round(rounded[top] + drift, 2)
    return rounded


def build_presence(corp_ids: list[str]) -> dict[str, dict[str, float]]:
    rng = random.Random(RNG_SEED)
    out: dict[str, dict[str, float]] = {}
    for sector in SECTORS:
        anchors = SECTOR_ANCHORS.get(sector, {})
        raw: dict[str, float] = {}
        for corp_id in corp_ids:
            w = FLOOR + rng.uniform(0.0, 0.85)
            w += anchors.get(corp_id, 0.0)
            raw[corp_id] = w
        out[sector] = _normalize(raw)
    return out


def main() -> int:
    corps_path = CATALOG / "corporations.json"
    corps = json.loads(corps_path.read_text(encoding="utf-8"))
    corp_ids = sorted(str(c["id"]) for c in corps)
    presence = build_presence(corp_ids)
    out_path = CATALOG / "corporate_presence.json"
    out_path.write_text(json.dumps(presence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {out_path} ({len(presence)} sectors, {len(corp_ids)} corps each)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
