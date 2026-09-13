#!/usr/bin/env python3
"""Validate ship templates fit chassis mass/volume envelopes (placeholder check)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import load_array, index_by_id, load_modules

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"


def main() -> int:
    chassis_by_id = index_by_id(load_array(CATALOG / "chassis.json"))
    modules_by_id = index_by_id(load_modules())
    ships = load_array(CATALOG / "ships.json")

    errors: list[str] = []
    for template in ships:
        ship_id = template["id"]
        chassis_id = template["chassis"]
        chassis = chassis_by_id.get(chassis_id)
        if chassis is None:
            errors.append(f"{ship_id}: unknown chassis {chassis_id}")
            continue

        dry_mass = float(chassis.get("mass", 0.0))
        volume_used = 0.0
        missing: list[str] = []
        for module_id in template.get("modules", []):
            module = modules_by_id.get(module_id)
            if module is None:
                missing.append(module_id)
                continue
            dry_mass += float(module.get("mass", 0.0))
            volume_used += float(module.get("volume", 0.0))

        if missing:
            errors.append(f"{ship_id}: missing modules {missing}")
            continue

        mass_limit = float(chassis.get("mass_limit", dry_mass))
        volume_limit = float(chassis.get("volume", volume_used))
        if dry_mass > mass_limit:
            errors.append(
                f"{ship_id}: dry mass {dry_mass:.1f} exceeds limit {mass_limit:.1f} t"
            )
        if volume_used > volume_limit:
            errors.append(
                f"{ship_id}: volume {volume_used:.1f} exceeds limit {volume_limit:.1f} m³"
            )

    traffic = json.loads((CATALOG / "traffic.json").read_text(encoding="utf-8"))
    ship_ids = {t["id"] for t in ships}
    prefixes = traffic.get("callsign_prefixes", {})
    roles = traffic.get("role_ship_templates", {})
    for template_id in prefixes:
        if template_id not in ship_ids:
            errors.append(f"traffic callsign prefix references unknown ship {template_id}")
    for role, entry in roles.items():
        ids = entry if isinstance(entry, list) else [entry]
        for template_id in ids:
            if template_id not in ship_ids:
                errors.append(f"traffic role {role} references unknown ship {template_id}")

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"OK: {len(ships)} ship templates validated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
