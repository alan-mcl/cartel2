#!/usr/bin/env python3
"""Validate cross-catalog referential integrity."""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import load_modules
from validate_sector_completeness import check as check_sector_completeness

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

LIFE_SUPPORT_MAKERS = {
    "Holt-Winters Corp",
    "Orion Aerospace",
    "ParaRamcoVidia",
    "General Industrial",
    "Oklahoma Combine",
    "BioGenesis Life Sciences",
    "Greenfields Corporation",
    "Four Rivers Zaibatsu",
    "Sakuraya Shinise",
    "Morrow & Sons",
    "Universal House",
    "Evergreen Group",
    "Atlas Concern",
    "Tukey Enterprises",
    "The Meridian Company",
}

LIFE_SUPPORT_FLAGS = {"ls_comfort", "ls_luxury", "ls_habitat"}
RETIRED_LIFE_SUPPORT_IDS = {"life_support_mk1", "life_support_a3"}
RETIRED_SENSOR_IDS = {
    "sensor_basic",
    "sensor_advanced",
    "sensor_thermal",
    "sensor_gravimetric",
    "sensor_em",
    "sensor_computational",
}
# SKU counts are floors, not exact expectations. Adding content must never fail validation;
# these only catch accidental bulk deletion. Do not convert them back to equality checks.
SENSOR_SKU_FLOOR = 8
LIFE_SUPPORT_SKU_FLOOR = 35
TRANSPORT_VOLUME_PER_CREW = {"spartan": 2.5, "comfort": 5.0, "luxury": 7.0}
HABITAT_VOLUME_PER_CREW = {"spartan": 8.0, "comfort": 11.0, "luxury": 14.0}
TRANSPORT_ONE_SEAT_COCKPIT_FLOOR = 4.0

PROPULSION_MAKERS = {
    "Holt-Winters Corp",
    "Orion Aerospace",
    "Oklahoma Combine",
    "Atlas Concern",
    "ParaRamcoVidia",
    "Four Rivers Zaibatsu",
    "The Meridian Company",
    "General Industrial",
    "Crown & Anchor",
    "House of Roth",
    "Chimera Corporation",
    "Sakuraya Shinise",
    "Seven Bells Inc",
    "Pacific Triad",
    "Tukey Enterprises",
    "Terra Nova",
    "Andean Consolidated",
    "Guangzhou Mercantile",
    "Orion Spur Company",
}

ENGINE_TYPES = {
    "chemical",
    "hydro_thermal",
    "electric_plasma",
    "direct_fusion",
    "antimatter",
    "gravitic",
}

RETIRED_PROPULSION_IDS = {
    "mark_1_fusion",
    "mark_3_fusion",
    "mark_2_antimatter",
    "gravitic_mk1",
}

PROPULSION_SKU_FLOOR = 40
# Every engine family must keep at least one SKU so a line cannot silently vanish. Gravitic is
# intentionally a single placeholder — see docs/design/backlog.md.
PROPULSION_TYPE_FLOORS = {
    "chemical": 1,
    "hydro_thermal": 1,
    "electric_plasma": 1,
    "direct_fusion": 1,
    "antimatter": 1,
    "gravitic": 1,
}

ENGINE_TYPE_LABELS = {
    "chemical": "Chemical",
    "hydro_thermal": "Hydro-thermal",
    "electric_plasma": "Electric plasma",
    "direct_fusion": "Direct fusion",
    "antimatter": "Antimatter",
    "gravitic": "Gravitic",
}

WEAPON_MAKERS = {
    "Holt-Winters Corp",
    "Orion Aerospace",
    "Oklahoma Combine",
    "Galactic Outcomes",
    "ParaRamcoVidia",
    "Four Rivers Zaibatsu",
    "Chimera Corporation",
    "Atlas Concern",
    "General Industrial",
    "Seven Bells Inc",
    "SnedeCorp",
    "Pacific Triad",
    "Tukey Enterprises",
    "Andean Consolidated",
    "Terra Nova",
    "Sakuraya Shinise",
    "Cult of Apex",
    "Guangzhou Mercantile",
    "Carthage Mercantile",
    "The Meridian Company",
}

ARMOUR_SHIELD_MAKERS = {
    "Holt-Winters Corp",
    "Oklahoma Combine",
    "Orion Aerospace",
    "ParaRamcoVidia",
    "General Industrial",
    "Chimera Corporation",
    "Atlas Concern",
    "Four Rivers Zaibatsu",
    "Galactic Outcomes",
    "Seven Bells Inc",
    "SnedeCorp",
    "The Meridian Company",
    "Sakuraya Shinise",
    "Pacific Triad",
    "Tukey Enterprises",
    "Terra Nova",
    "Andean Consolidated",
    "Evergreen Group",
    "Cult of Apex",
}

WEAPON_TYPES = {
    "mass_driver",
    "laser",
    "plasma",
    "scatter",
    "rocket",
    "missile",
    "cyber",
}

DELIVERY_TYPES = {"ballistic", "beam", "plasma", "guided", "cyber"}

SHIELD_TYPES = {"deflector", "energy", "electronic"}

PACKET_TYPES = {"kinetic", "concussive", "energy", "cyber"}

WEAPON_SKU_FLOOR = 25
ARMOUR_SKU_FLOOR = 12
SHIELD_SKU_FLOOR = 10
POINT_DEFENCE_SKU_FLOOR = 6
CYBER_DEFENCE_SKU_FLOOR = 4


def load_array(path: Path) -> list:
    return json.loads(path.read_text(encoding="utf-8"))


def load_object(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def index_by_id(items: list) -> dict:
    return {item["id"]: item for item in items}


def life_support_band(capabilities: list) -> str:
    caps = {str(cap) for cap in capabilities}
    if "ls_luxury" in caps:
        return "luxury"
    if "ls_comfort" in caps:
        return "comfort"
    return "spartan"


def life_support_volume_floor(crew: float, capabilities: list) -> float:
    caps = [str(cap) for cap in capabilities]
    band = life_support_band(caps)
    habitat = "ls_habitat" in caps
    per_crew = (HABITAT_VOLUME_PER_CREW if habitat else TRANSPORT_VOLUME_PER_CREW)[band]
    floor = per_crew * crew
    if not habitat and crew <= 1.0:
        floor = max(floor, TRANSPORT_ONE_SEAT_COCKPIT_FLOOR)
    return floor


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

    modules = load_modules()
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

    life_support_count = 0
    for module in modules:
        if not isinstance(module, dict):
            continue
        module_id = str(module.get("id", ""))
        if module_id in RETIRED_LIFE_SUPPORT_IDS:
            errors.append(
                f"modules.json: retired life support id '{module_id}' still present"
            )
        if str(module.get("category", "")) != "life_support":
            continue
        life_support_count += 1
        for field in ("maker", "brand", "life_support_capacity", "compute_demand"):
            if field not in module:
                errors.append(f"life support module {module_id}: missing {field}")
        maker = str(module.get("maker", ""))
        if maker and maker not in LIFE_SUPPORT_MAKERS:
            errors.append(f"life support module {module_id}: unknown maker '{maker}'")
        if str(module.get("mount", "")) != "system":
            errors.append(f"life support module {module_id}: mount must be 'system'")
        if "fuel_consumption" in module:
            errors.append(
                f"life support module {module_id}: fuel_consumption must not be set"
            )
        crew = float(module.get("life_support_capacity", 0.0))
        if crew < 1.0 or crew > 6.0:
            errors.append(
                f"life support module {module_id}: life_support_capacity must be 1–6"
            )
        capabilities = module.get("capabilities", [])
        if not isinstance(capabilities, list):
            errors.append(
                f"life support module {module_id}: capabilities must be an array"
            )
            continue
        for cap in capabilities:
            cap_id = str(cap)
            if cap_id not in LIFE_SUPPORT_FLAGS:
                errors.append(
                    f"life support module {module_id}: invalid capability '{cap_id}'"
                )
        volume = float(module.get("volume", 0.0))
        floor = life_support_volume_floor(crew, capabilities)
        if volume + 1e-6 < floor:
            errors.append(
                f"life support module {module_id}: volume {volume} m³ below "
                f"{floor} m³ floor for crew {crew:g}"
            )
    if life_support_count < LIFE_SUPPORT_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {LIFE_SUPPORT_SKU_FLOOR} life support SKUs, "
            f"found {life_support_count}"
        )

    propulsion_count = 0
    propulsion_type_counts = {key: 0 for key in PROPULSION_TYPE_FLOORS}
    for module in modules:
        if not isinstance(module, dict):
            continue
        module_id = str(module.get("id", ""))
        if module_id in RETIRED_PROPULSION_IDS:
            errors.append(
                f"modules.json: retired propulsion id '{module_id}' still present"
            )
        if str(module.get("category", "")) != "propulsion":
            continue
        propulsion_count += 1
        for field in ("maker", "brand", "engine_type", "thrust"):
            if field not in module:
                errors.append(f"propulsion module {module_id}: missing {field}")
        maker = str(module.get("maker", ""))
        if maker and maker not in PROPULSION_MAKERS:
            errors.append(f"propulsion module {module_id}: unknown maker '{maker}'")
        if maker == "Bayes Inc":
            errors.append(f"propulsion module {module_id}: Bayes Inc must not make engines")
        engine_type = str(module.get("engine_type", ""))
        if engine_type and engine_type not in ENGINE_TYPES:
            errors.append(f"propulsion module {module_id}: invalid engine_type '{engine_type}'")
        if engine_type in propulsion_type_counts:
            propulsion_type_counts[engine_type] += 1
        if str(module.get("mount", "")) != "main_engine":
            errors.append(f"propulsion module {module_id}: mount must be 'main_engine'")
    if propulsion_count < PROPULSION_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {PROPULSION_SKU_FLOOR} propulsion SKUs, "
            f"found {propulsion_count}"
        )
    for engine_type, minimum in PROPULSION_TYPE_FLOORS.items():
        found = propulsion_type_counts.get(engine_type, 0)
        if found < minimum:
            errors.append(
                f"modules.json: expected at least {minimum} {engine_type} engines, found {found}"
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

    ammunition = index_by_id(load_array(CATALOG / "ammunition.json"))
    weapon_count = armour_count = shield_count = pd_count = cyber_def_count = 0
    for module in modules:
        if not isinstance(module, dict):
            continue
        module_id = str(module.get("id", ""))
        category = str(module.get("category", ""))
        if category == "weapon":
            weapon_count += 1
            for field in ("maker", "brand", "weapon_type", "delivery_type"):
                if field not in module:
                    errors.append(f"weapon module {module_id}: missing {field}")
            maker = str(module.get("maker", ""))
            if maker == "Bayes Inc":
                errors.append(f"weapon module {module_id}: Bayes Inc must not make weapons")
            if maker and maker not in WEAPON_MAKERS:
                errors.append(f"weapon module {module_id}: unknown maker '{maker}'")
            weapon_type = str(module.get("weapon_type", ""))
            if weapon_type and weapon_type not in WEAPON_TYPES:
                errors.append(f"weapon module {module_id}: invalid weapon_type '{weapon_type}'")
            delivery_type = str(module.get("delivery_type", ""))
            if delivery_type and delivery_type not in DELIVERY_TYPES:
                errors.append(f"weapon module {module_id}: invalid delivery_type '{delivery_type}'")
            if weapon_type == "plasma" and delivery_type != "plasma":
                errors.append(f"weapon module {module_id}: plasma weapons require plasma delivery")
            ammo_type = str(module.get("ammunition_type", ""))
            has_packets = "damage_packets" in module
            if ammo_type:
                if has_packets:
                    errors.append(
                        f"weapon module {module_id}: must not set damage_packets when using ammo"
                    )
                if ammo_type not in ammunition:
                    errors.append(
                        f"weapon module {module_id}: unknown ammunition '{ammo_type}'"
                    )
            elif not has_packets:
                errors.append(f"weapon module {module_id}: needs damage_packets or ammunition_type")
        elif category == "armour":
            armour_count += 1
            for field in ("maker", "brand", "hits", "protection"):
                if field not in module:
                    errors.append(f"armour module {module_id}: missing {field}")
            maker = str(module.get("maker", ""))
            if maker == "Bayes Inc":
                errors.append(f"armour module {module_id}: Bayes Inc must not make armour")
            if maker and maker not in ARMOUR_SHIELD_MAKERS:
                errors.append(f"armour module {module_id}: unknown maker '{maker}'")
        elif category == "shield":
            shield_count += 1
            for field in ("maker", "brand", "shield_type", "shield_capacity", "protection", "regen"):
                if field not in module:
                    errors.append(f"shield module {module_id}: missing {field}")
            maker = str(module.get("maker", ""))
            if maker and maker not in ARMOUR_SHIELD_MAKERS:
                errors.append(f"shield module {module_id}: unknown maker '{maker}'")
            shield_type = str(module.get("shield_type", ""))
            if shield_type and shield_type not in SHIELD_TYPES:
                errors.append(f"shield module {module_id}: invalid shield_type '{shield_type}'")
        elif category == "point_defence":
            pd_count += 1
            for field in ("maker", "brand", "intercept_chance"):
                if field not in module:
                    errors.append(f"point_defence module {module_id}: missing {field}")
            maker = str(module.get("maker", ""))
            if maker and maker not in ARMOUR_SHIELD_MAKERS:
                errors.append(f"point_defence module {module_id}: unknown maker '{maker}'")
        elif category == "cyber_defence":
            cyber_def_count += 1
            for field in ("maker", "brand", "protection"):
                if field not in module:
                    errors.append(f"cyber_defence module {module_id}: missing {field}")
            maker = str(module.get("maker", ""))
            if maker and maker not in ARMOUR_SHIELD_MAKERS:
                errors.append(f"cyber_defence module {module_id}: unknown maker '{maker}'")

    if weapon_count < WEAPON_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {WEAPON_SKU_FLOOR} weapon SKUs, "
            f"found {weapon_count}"
        )
    if armour_count < ARMOUR_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {ARMOUR_SKU_FLOOR} armour SKUs, "
            f"found {armour_count}"
        )
    if shield_count < SHIELD_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {SHIELD_SKU_FLOOR} shield SKUs, "
            f"found {shield_count}"
        )
    if pd_count < POINT_DEFENCE_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {POINT_DEFENCE_SKU_FLOOR} point_defence SKUs, "
            f"found {pd_count}"
        )
    if cyber_def_count < CYBER_DEFENCE_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {CYBER_DEFENCE_SKU_FLOOR} cyber_defence SKUs, "
            f"found {cyber_def_count}"
        )

    sensor_count = sum(1 for m in modules if m.get("category") == "sensor")
    if sensor_count < SENSOR_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {SENSOR_SKU_FLOOR} sensor SKUs, "
            f"found {sensor_count}"
        )

    signature_channels = {"thermal", "gravitational", "electromagnetic", "computational"}
    for module in modules:
        module_id = str(module.get("id", ""))
        signature = module.get("signature")
        if not isinstance(signature, dict):
            errors.append(f"modules.json: {module_id} missing signature object")
            continue
        missing = signature_channels - set(signature.keys())
        if missing:
            errors.append(f"modules.json: {module_id} signature missing {sorted(missing)}")
        if module.get("category") == "sensor":
            if not str(module.get("maker", "")):
                errors.append(f"modules.json: {module_id} missing maker")
            if not str(module.get("brand", "")):
                errors.append(f"modules.json: {module_id} missing brand")
            if "has_active" not in module:
                errors.append(f"modules.json: {module_id} missing has_active")
            if "sensor_range" not in module:
                errors.append(f"modules.json: {module_id} missing sensor_range")
            sensitivity = module.get("sensor_sensitivity")
            if not isinstance(sensitivity, dict):
                errors.append(f"modules.json: {module_id} missing sensor_sensitivity")
            elif signature_channels - set(sensitivity.keys()):
                errors.append(f"modules.json: {module_id} sensor_sensitivity incomplete")
            passive_sensitivity = module.get("sensor_sensitivity_passive")
            if passive_sensitivity is not None and not isinstance(passive_sensitivity, dict):
                errors.append(
                    f"modules.json: {module_id} sensor_sensitivity_passive must be an object"
                )

    for template in ships.values():
        has_computer = False
        has_life_support = False
        has_propulsion = False
        template_id = str(template.get("id", ""))
        chassis_id = str(template.get("chassis", ""))
        chassis_def = chassis.get(chassis_id, {})
        volume_used = 0.0
        dry_mass = float(chassis_def.get("mass", 0.0))
        for module_id in template.get("modules", []):
            module_id = str(module_id)
            if module_id in RETIRED_PROPULSION_IDS:
                errors.append(
                    f"ship {template_id}: references retired propulsion '{module_id}'"
                )
            if module_id in RETIRED_POWER_IDS:
                errors.append(
                    f"ship {template_id}: references retired power plant '{module_id}'"
                )
            if module_id in RETIRED_COMPUTER_IDS:
                errors.append(
                    f"ship {template_id}: references retired computer '{module_id}'"
                )
            if module_id in RETIRED_LIFE_SUPPORT_IDS:
                errors.append(
                    f"ship {template_id}: references retired life support '{module_id}'"
                )
            if module_id in RETIRED_SENSOR_IDS:
                errors.append(
                    f"ship {template_id}: references retired sensor '{module_id}'"
                )
            module = modules_by_id.get(module_id)
            if module is None:
                continue
            volume_used += float(module.get("volume", 0.0))
            dry_mass += float(module.get("mass", 0.0))
            category = str(module.get("category", ""))
            if category == "power" and module_id in RETIRED_POWER_IDS:
                errors.append(
                    f"ship {template_id}: references retired power plant '{module_id}'"
                )
            if category == "computer":
                has_computer = True
                if str(module.get("core_type", "")) == "quantum":
                    errors.append(
                        f"ship {template_id}: template must not default to quantum core '{module_id}'"
                    )
            if category == "life_support":
                has_life_support = True
                if float(module.get("life_support_capacity", 0.0)) < 1.0:
                    errors.append(
                        f"ship {template_id}: life support '{module_id}' capacity below 1"
                    )
            if category == "propulsion":
                has_propulsion = True
        if not has_computer:
            errors.append(f"ship {template_id}: missing computer module")
        if not has_life_support:
            errors.append(f"ship {template_id}: missing life support module")
        if not has_propulsion:
            errors.append(f"ship {template_id}: missing propulsion module")
        if chassis_def:
            volume_limit = float(chassis_def.get("volume", 0.0))
            mass_limit = float(chassis_def.get("mass_limit", 0.0))
            if volume_used > volume_limit + 1e-6:
                errors.append(
                    f"ship {template_id}: assembled volume {volume_used:.2f} m³ "
                    f"exceeds chassis {volume_limit:.1f} m³"
                )
            if dry_mass > mass_limit + 1e-6:
                errors.append(
                    f"ship {template_id}: assembled mass {dry_mass:.2f} t "
                    f"exceeds mass_limit {mass_limit:.1f} t"
                )

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

    errors.extend(check_sector_completeness(CATALOG))

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
