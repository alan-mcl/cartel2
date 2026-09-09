#!/usr/bin/env python3
"""Validate cross-catalog referential integrity."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"

POWER_PLANT_MAKERS = {
    "Holt-Winters Corp",
    "ParaRamcoVidia",
    "General Industrial",
    "Orion Aerospace",
    "Oklahoma Combine",
    "Four Rivers Zaibatsu",
    "Atlas Concern",
    "House of Roth",
    "The Meridian Company",
    "Seven Bells Inc",
    "Sakuraya Shinise",
    "Andean Consolidated",
    "Terra Nova",
    "Evergreen Group",
    "Tukey Enterprises",
    "Chettiar Holdings",
    "Guangzhou Mercantile",
    "Crown & Anchor",
    "Pacific Triad",
}

POWER_PLANT_TYPES = {"fission", "fusion", "radioisotope"}
RETIRED_POWER_IDS = {"fusion_plant_mk1", "fusion_plant_mk2"}

COMPUTE_CORE_MAKERS = {
    "SnedeCorp",
    "ParaRamcoVidia",
    "Monday Corporation",
    "Mercury Communications",
    "Chimera Corporation",
    "Seven Bells Inc",
    "Orion Aerospace",
    "Holt-Winters Corp",
    "Sakuraya Shinise",
    "Four Rivers Zaibatsu",
    "Oklahoma Combine",
    "Tukey Enterprises",
    "The Meridian Company",
    "Cult of Apex",
    "LiveWorlds",
    "Orion Spur Company",
}

COMPUTE_CORE_TYPES = {"silicon", "photon", "quantum"}
RETIRED_COMPUTER_IDS = {
    "nav_combat_core_mk1",
    "nav_combat_core_mk2",
    "targeting_core_mk2",
}


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

    modules = load_array(CATALOG / "modules.json")
    modules_by_id = index_by_id(modules)
    computer_count = 0
    for module in modules:
        if not isinstance(module, dict):
            continue
        module_id = str(module.get("id", ""))
        if module_id in RETIRED_COMPUTER_IDS:
            errors.append(
                f"modules.json: retired computer id '{module_id}' still present"
            )
        if str(module.get("category", "")) != "computer":
            continue
        computer_count += 1
        for field in ("maker", "brand", "core_type", "compute_capacity"):
            if field not in module:
                errors.append(f"computer module {module_id}: missing {field}")
        maker = str(module.get("maker", ""))
        if maker and maker not in COMPUTE_CORE_MAKERS:
            errors.append(f"computer module {module_id}: unknown maker '{maker}'")
        core_type = str(module.get("core_type", ""))
        if core_type and core_type not in COMPUTE_CORE_TYPES:
            errors.append(f"computer module {module_id}: invalid core_type '{core_type}'")
        if str(module.get("mount", "")) != "system":
            errors.append(f"computer module {module_id}: mount must be 'system'")
        if "compute_demand" in module:
            errors.append(
                f"computer module {module_id}: compute_demand must not be set on cores"
            )
        capabilities = module.get("capabilities", [])
        if not isinstance(capabilities, list) or "basic_hud" not in capabilities:
            errors.append(
                f"computer module {module_id}: must include basic_hud capability"
            )

    power_count = 0
    for module in modules:
        if not isinstance(module, dict):
            continue
        module_id = str(module.get("id", ""))
        if module_id in RETIRED_POWER_IDS:
            errors.append(f"modules.json: retired power plant id '{module_id}' still present")
        if str(module.get("category", "")) != "power":
            continue
        power_count += 1
        for field in ("maker", "brand", "plant_type", "power_generation"):
            if field not in module:
                errors.append(f"power module {module_id}: missing {field}")
        maker = str(module.get("maker", ""))
        if maker and maker not in POWER_PLANT_MAKERS:
            errors.append(f"power module {module_id}: unknown maker '{maker}'")
        plant_type = str(module.get("plant_type", ""))
        if plant_type and plant_type not in POWER_PLANT_TYPES:
            errors.append(f"power module {module_id}: invalid plant_type '{plant_type}'")
        if str(module.get("mount", "")) != "power":
            errors.append(f"power module {module_id}: mount must be 'power'")
        fuel = float(module.get("fuel_consumption", -1.0))
        generation = float(module.get("power_generation", 0.0))
        if plant_type == "radioisotope":
            if fuel != 0.0:
                errors.append(
                    f"power module {module_id}: radioisotope fuel_consumption must be 0"
                )
            if generation > 12.0:
                errors.append(
                    f"power module {module_id}: radioisotope output exceeds 12 MW"
                )

    for template in ships.values():
        has_computer = False
        for module_id in template.get("modules", []):
            module_id = str(module_id)
            if module_id in RETIRED_POWER_IDS:
                errors.append(
                    f"ship {template['id']}: references retired power plant '{module_id}'"
                )
            if module_id in RETIRED_COMPUTER_IDS:
                errors.append(
                    f"ship {template['id']}: references retired computer '{module_id}'"
                )
            module = modules_by_id.get(module_id)
            if module is None:
                continue
            category = str(module.get("category", ""))
            if category == "power" and module_id in RETIRED_POWER_IDS:
                errors.append(
                    f"ship {template['id']}: references retired power plant '{module_id}'"
                )
            if category == "computer":
                has_computer = True
                if str(module.get("core_type", "")) == "quantum":
                    errors.append(
                        f"ship {template['id']}: template must not default to quantum core '{module_id}'"
                    )
        if not has_computer:
            errors.append(f"ship {template['id']}: missing computer module")

    buildings = load_array(CATALOG / "buildings.json")
    for chassis_id, chassis_def in chassis.items():
        if "cost" not in chassis_def:
            errors.append(f"chassis {chassis_id}: missing cost")

    for building in buildings:
        if not isinstance(building, dict):
            continue
        building_id = str(building.get("id", ""))
        building_type = str(building.get("type", ""))
        stock = building.get("stock", [])
        if not isinstance(stock, list):
            continue
        if building_type not in ("ship_dealer", "chassis_dealer"):
            continue
        for stock_id in stock:
            stock_id = str(stock_id)
            if building_type == "ship_dealer" and stock_id not in ships:
                errors.append(
                    f"building {building_id}: unknown ship template '{stock_id}'"
                )
            if building_type == "chassis_dealer" and stock_id not in chassis:
                errors.append(
                    f"building {building_id}: unknown chassis '{stock_id}'"
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
