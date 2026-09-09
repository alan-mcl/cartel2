#!/usr/bin/env python3
"""Validate cross-catalog referential integrity."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"


def load_array(path: Path) -> list:
    return json.loads(path.read_text(encoding="utf-8"))


def load_object(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def index_by_id(items: list) -> dict:
    return {item["id"]: item for item in items}


def collect_interactable_refs(value: object, found: set[str]) -> None:
    if isinstance(value, dict):
        interactable_id = value.get("interactable")
        if interactable_id:
            found.add(str(interactable_id))
        for nested in value.values():
            collect_interactable_refs(nested, found)
    elif isinstance(value, list):
        for item in value:
            collect_interactable_refs(item, found)


def main() -> int:
    sectors = index_by_id(load_array(CATALOG / "sectors.json"))
    habitats = index_by_id(load_array(CATALOG / "habitats.json"))
    chassis = index_by_id(load_array(CATALOG / "chassis.json"))
    ships = index_by_id(load_array(CATALOG / "ships.json"))
    interactables = index_by_id(load_array(CATALOG / "interactables.json"))
    routes = load_array(CATALOG / "routes.json")
    unspaces = load_array(CATALOG / "unspaces.json")
    worlds = load_object(CATALOG / "worlds.json")
    player = load_object(CATALOG / "player.json")
    backgrounds_doc = load_object(CATALOG / "backgrounds.json")

    errors: list[str] = []

    if "gst" not in player:
        errors.append("player.json: missing gst block")

    default_background_id = str(backgrounds_doc.get("default_id", ""))
    backgrounds = backgrounds_doc.get("backgrounds", [])
    if not isinstance(backgrounds, list):
        errors.append("backgrounds.json: backgrounds must be an array")
        backgrounds = []

    background_ids: set[str] = set()
    for background in backgrounds:
        if not isinstance(background, dict):
            continue
        background_id = str(background.get("id", ""))
        if not background_id:
            errors.append("backgrounds.json: background entry missing id")
            continue
        if background_id in background_ids:
            errors.append(f"backgrounds.json: duplicate background id '{background_id}'")
        background_ids.add(background_id)

        habitat_id = str(background.get("habitat_id", ""))
        if habitat_id and habitat_id not in habitats:
            errors.append(
                f"background {background_id}: unknown habitat '{habitat_id}'"
            )

        ship_entries = background.get("ships", [])
        if not isinstance(ship_entries, list):
            errors.append(f"background {background_id}: ships must be an array")
            continue
        for ship in ship_entries:
            if not isinstance(ship, dict):
                continue
            template_id = str(ship.get("template_id", ""))
            chassis_id = str(ship.get("chassis_id", ""))
            if template_id and template_id not in ships:
                errors.append(
                    f"background {background_id}: unknown ship template '{template_id}'"
                )
            if chassis_id and chassis_id not in chassis:
                errors.append(
                    f"background {background_id}: unknown chassis '{chassis_id}'"
                )
            for module in ship.get("modules", []):
                if not isinstance(module, dict):
                    continue
                module_id = str(module.get("module_id", ""))
                # module validation handled elsewhere; skip here

    if default_background_id and default_background_id not in background_ids:
        errors.append(
            f"backgrounds.json: default_id '{default_background_id}' not found"
        )

    for route in routes:
        route_id = str(route.get("id", "?"))
        for end in ("a", "b"):
            sector_id = str(route.get(end, ""))
            if sector_id and sector_id not in sectors:
                errors.append(f"route {route_id}: unknown sector '{sector_id}'")
        n = int(route.get("n", 0))
        if n <= 0:
            errors.append(f"route {route_id}: invalid n={n}")
        if "solution_ab" not in route or "solution_ba" not in route:
            errors.append(f"route {route_id}: missing solution_ab/solution_ba")

    for unspace in unspaces:
        unspace_id = str(unspace.get("id", ""))
        if not unspace_id:
            errors.append("unspace entry missing id")
            continue
        if unspace_id not in worlds:
            errors.append(f"unspace {unspace_id}: missing world entry in worlds.json")

    for world_id, world_data in worlds.items():
        refs: set[str] = set()
        collect_interactable_refs(world_data, refs)
        for interactable_id in sorted(refs):
            if interactable_id not in interactables:
                errors.append(
                    f"world {world_id}: unknown interactable '{interactable_id}'"
                )

    for unspace in unspaces:
        unspace_id = str(unspace.get("id", ""))
        field = unspace.get("field", {})
        if not isinstance(field, dict):
            continue
        portal = field.get("portal", {})
        if not isinstance(portal, dict):
            continue
        interactable_id = str(portal.get("interactable", ""))
        if interactable_id and interactable_id not in interactables:
            errors.append(
                f"unspace {unspace_id}: unknown portal interactable '{interactable_id}'"
            )

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(
        f"OK: catalog refs validated ({len(sectors)} sectors, "
        f"{len(background_ids)} backgrounds, {len(routes)} routes, "
        f"{len(unspaces)} unspaces, {len(worlds)} worlds)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
