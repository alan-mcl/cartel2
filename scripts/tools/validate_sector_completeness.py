#!/usr/bin/env python3
"""Validate that each sector is complete across catalog files."""

from __future__ import annotations

from pathlib import Path

from catalog_io import index_by_id, load_array, load_object


def _has_public_n4_route(routes: list, sector_a: str, sector_b: str) -> bool:
    for route in routes:
        if not isinstance(route, dict):
            continue
        a = str(route.get("a", ""))
        b = str(route.get("b", ""))
        if not ((a == sector_a and b == sector_b) or (a == sector_b and b == sector_a)):
            continue
        translations = route.get("translations", [])
        if not isinstance(translations, list):
            continue
        for entry in translations:
            if isinstance(entry, dict) and int(entry.get("n", 0)) == 4:
                return True
    return False


def _validate_translate_interactable(
    errors: list[str],
    label: str,
    interactable_id: str,
    interactables: dict[str, dict],
) -> None:
    if not interactable_id:
        errors.append(f"{label}: missing interactable")
        return
    if interactable_id not in interactables:
        errors.append(f"{label}: unknown interactable '{interactable_id}'")
        return
    gate = interactables[interactable_id]
    if str(gate.get("kind", "")) != "translate":
        errors.append(f"{label}: interactable '{interactable_id}' must be kind translate")


def check(catalog_dir: Path) -> list[str]:
    errors: list[str] = []
    sectors = index_by_id(load_array(catalog_dir / "sectors.json"))
    habitats = load_array(catalog_dir / "habitats.json")
    buildings = index_by_id(load_array(catalog_dir / "buildings.json"))
    interactables = index_by_id(load_array(catalog_dir / "interactables.json"))
    economies = index_by_id(load_array(catalog_dir / "economies.json"))
    routes = load_array(catalog_dir / "routes.json")
    worlds = load_object(catalog_dir / "worlds.json")

    habitats_by_sector: dict[str, list[dict]] = {}
    for habitat in habitats:
        if not isinstance(habitat, dict):
            continue
        sector_id = str(habitat.get("sector_id", ""))
        if not sector_id:
            errors.append(f"habitat {habitat.get('id', '?')}: missing sector_id")
            continue
        habitats_by_sector.setdefault(sector_id, []).append(habitat)

    route_endpoints: dict[str, int] = {}
    for route in routes:
        if not isinstance(route, dict):
            continue
        for end in ("a", "b"):
            sector_id = str(route.get(end, ""))
            if sector_id:
                route_endpoints[sector_id] = route_endpoints.get(sector_id, 0) + 1

    for sector_id, sector in sectors.items():
        label = f"sector {sector_id}"

        matched = habitats_by_sector.get(sector_id, [])
        if len(matched) == 0:
            errors.append(f"{label}: no habitat with sector_id")
        elif len(matched) > 1:
            errors.append(
                f"{label}: expected one habitat, found {len(matched)} "
                f"({', '.join(str(h.get('id', '?')) for h in matched)})"
            )

        if sector_id not in worlds:
            errors.append(f"{label}: missing world entry in worlds.json")
            continue

        world_data = worlds[sector_id]
        if not isinstance(world_data, dict):
            errors.append(f"{label}: world entry must be an object")
            continue

        if sector_id not in economies:
            errors.append(f"{label}: missing economy entry in economies.json")

        if route_endpoints.get(sector_id, 0) < 1:
            errors.append(f"{label}: no route references this sector")

        if len(matched) != 1:
            continue

        habitat = matched[0]
        habitat_id = str(habitat.get("id", ""))

        default_building = str(habitat.get("default_building", ""))
        if default_building and default_building not in buildings:
            errors.append(
                f"{label}: habitat default_building '{default_building}' unknown"
            )

        building_ids = habitat.get("buildings", [])
        if not isinstance(building_ids, list):
            errors.append(f"{label}: habitat buildings must be an array")
            building_ids = []

        for building_id in building_ids:
            bid = str(building_id)
            if bid and bid not in buildings:
                errors.append(f"{label}: unknown building '{bid}' on habitat")

        orbital_ring = world_data.get("orbital_ring", {})
        if not isinstance(orbital_ring, dict):
            errors.append(f"{label}: world missing orbital_ring")
            orbital_ring = {}

        orbitals = orbital_ring.get("orbitals", [])
        if not isinstance(orbitals, list):
            errors.append(f"{label}: orbital_ring orbitals must be an array")
            orbitals = []

        habitat_orbitals = [
            o
            for o in orbitals
            if isinstance(o, dict) and str(o.get("kind", "")) == "habitat"
        ]
        if len(habitat_orbitals) == 0:
            errors.append(f"{label}: world has no orbital with kind habitat")
        elif len(habitat_orbitals) > 1:
            errors.append(
                f"{label}: world has {len(habitat_orbitals)} habitat orbitals, expected one"
            )
        else:
            habitat_interactable_id = str(habitat_orbitals[0].get("interactable", ""))
            if not habitat_interactable_id:
                errors.append(f"{label}: habitat orbital missing interactable")
            elif habitat_interactable_id not in interactables:
                errors.append(
                    f"{label}: unknown habitat interactable '{habitat_interactable_id}'"
                )
            else:
                dock = interactables[habitat_interactable_id]
                if str(dock.get("kind", "")) != "dock":
                    errors.append(
                        f"{label}: interactable '{habitat_interactable_id}' must be kind dock"
                    )
                dock_location = str(dock.get("dock_location_id", ""))
                if dock_location != habitat_id:
                    errors.append(
                        f"{label}: dock interactable '{habitat_interactable_id}' "
                        f"dock_location_id '{dock_location}' != habitat id '{habitat_id}'"
                    )

        jump_gate = world_data.get("jump_gate")
        translation_beacon = world_data.get("translation_beacon")
        has_gate = isinstance(jump_gate, dict) and bool(jump_gate)
        has_beacon = isinstance(translation_beacon, dict) and bool(translation_beacon)
        if has_gate and has_beacon:
            errors.append(f"{label}: world has both jump_gate and translation_beacon")
        elif not has_gate and not has_beacon:
            errors.append(f"{label}: world needs jump_gate or translation_beacon")
        elif has_gate:
            gate_interactable_id = str(jump_gate.get("interactable", ""))
            _validate_translate_interactable(
                errors, f"{label} jump_gate", gate_interactable_id, interactables
            )
        else:
            beacon_interactable_id = str(translation_beacon.get("interactable", ""))
            _validate_translate_interactable(
                errors,
                f"{label} translation_beacon",
                beacon_interactable_id,
                interactables,
            )
            destination = str(translation_beacon.get("destination", ""))
            if not destination:
                errors.append(f"{label}: translation_beacon missing destination")
            elif destination not in sectors:
                errors.append(
                    f"{label}: translation_beacon unknown destination '{destination}'"
                )
            elif not _has_public_n4_route(routes, sector_id, destination):
                errors.append(
                    f"{label}: no public n=4 route between '{sector_id}' and '{destination}'"
                )

    for sector_id, matched in habitats_by_sector.items():
        if sector_id not in sectors:
            errors.append(
                f"habitat sector_id '{sector_id}': unknown sector "
                f"({', '.join(str(h.get('id', '?')) for h in matched)})"
            )

    return errors


def main() -> int:
    import sys

    catalog_dir = Path(__file__).resolve().parents[2] / "data" / "catalog"
    errors = check(catalog_dir)
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1
    print("OK: sector completeness validated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
