#!/usr/bin/env python3
"""Mechanical session facade -> slice retarget for R8 (dev-only)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

FIELD_SLICE: dict[str, str] = {}
for name, fields in (
    (
        "player",
        (
            "callsign",
            "portrait_path",
            "background_id",
            "objective",
            "last_log",
            "sandbox",
            "salvaged_ids",
            "inspected_ids",
            "spare_parts",
        ),
    ),
    (
        "world",
        (
            "sector_id",
            "location_name",
            "docked",
            "habitat_id",
            "building_id",
            "in_unspace",
            "unspace_n",
            "unspace_world_id",
            "unspace_solution",
            "translation_stability",
            "pending_destination_id",
            "gst_seconds",
            "run_seed",
            "orbital_phase_by_sector",
            "market_quotes",
            "market_quotes_day",
            "fuel_quotes",
            "fuel_quotes_day",
            "route_friction_delta",
        ),
    ),
    ("fleet", ("owned_ships", "current_ship_id")),
    ("wallet", ("credits",)),
    (
        "combat",
        (
            "hull",
            "max_hull",
            "power_integrity_lost",
            "compute_integrity_lost",
            "shield_charges",
        ),
    ),
):
    for f in fields:
        FIELD_SLICE[f] = name

SESSION_ROOT = r"(_?session|game_session|career_session|gate_session)"

PATTERN = re.compile(
    rf"\b{SESSION_ROOT}\.(?!(?:player|world|fleet|wallet|combat)\.)"
    rf"({'|'.join(sorted(FIELD_SLICE.keys(), key=len, reverse=True))})\b"
)


def retarget(text: str) -> str:
    def repl(m: re.Match[str]) -> str:
        root = m.group(1)
        field = m.group(2)
        return f"{root}.{FIELD_SLICE[field]}.{field}"

    return PATTERN.sub(repl, text)


def process_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    updated = retarget(text)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
        return True
    return False


def main() -> int:
    dirs = [
        ROOT / "scripts" / "gameplay",
        ROOT / "scripts" / "presentation",
        ROOT / "scripts" / "ui",
    ]
    changed = 0
    for d in dirs:
        for path in sorted(d.glob("*.gd")):
            if process_file(path):
                changed += 1
                print(path.relative_to(ROOT))
    print(f"updated {changed} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())