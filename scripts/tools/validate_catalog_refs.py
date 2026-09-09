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
    interactables = index_by_id(load_array(CATALOG / "interactables.json"))
    routes = load_array(CATALOG / "routes.json")
    unspaces = load_array(CATALOG / "unspaces.json")
    worlds = load_object(CATALOG / "worlds.json")

    errors: list[str] = []

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
        f"{len(routes)} routes, {len(unspaces)} unspaces, {len(worlds)} worlds)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
