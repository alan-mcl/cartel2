#!/usr/bin/env python3
"""Validate that each sector is complete across catalog files."""

from __future__ import annotations

from pathlib import Path

from catalog_io import index_by_id, load_array, load_object


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

        jump_gate = world_data.get("jump_gate", {})
        if not isinstance(jump_gate, dict):
            errors.append(f"{label}: world missing jump_gate")
            jump_gate = {}

        gate_interactable_id = str(jump_gate.get("interactable", ""))
        if not gate_interactable_id:
            errors.append(f"{label}: jump_gate missing interactable")
        elif gate_interactable_id not in interactables:
            errors.append(
                f"{label}: unknown jump_gate interactable '{gate_interactable_id}'"
            )
        else:
            gate = interactables[gate_interactable_id]
            if str(gate.get("kind", "")) != "translate":
                errors.append(
                    f"{label}: interactable '{gate_interactable_id}' must be kind translate"
                )

    for sector_id, matched in habitats_by_sector.items():
        if sector_id not in sectors:
            errors.append(
                f"habitat sector_id '{sector_id}': unknown sector "
                f"({', '.join(str(h.get('id', '?')) for h in matched)})"
            )

    return errors


def main() -> int:
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
