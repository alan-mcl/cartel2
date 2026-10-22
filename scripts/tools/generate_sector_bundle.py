#!/usr/bin/env python3
"""Generate or patch catalog entries for one planetary sector from a compact spec."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import CATALOG, index_by_id, load_array, load_object
from generate_corporate_presence import build_sector_presence, godot_string_hash

DEFAULT_HABITAT_SPRITE = "res://assets/world/habitat_proxima.svg"
DEFAULT_PLANET_SPRITE = "res://assets/world/planet.png"
ORBITAL_SPRITE_DIR = Path(__file__).resolve().parents[2] / "assets" / "world" / "orbitals"


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def write_json_matching(path: Path, data: object) -> None:
    indent: str | int = 2
    if path.exists():
        first = path.read_text(encoding="utf-8").splitlines()
        if len(first) > 1 and first[1].startswith("\t"):
            indent = "\t"
    path.write_text(json.dumps(data, indent=indent) + "\n", encoding="utf-8")


def corporate_office_count(sector_id: str) -> int:
    return 2 + (godot_string_hash(sector_id) % 4)


def top_corporation_ids(presence: dict, count: int) -> list[str]:
    ranked = sorted(
        presence.items(),
        key=lambda item: (-float(item[1]), str(item[0])),
    )
    return [str(corp_id) for corp_id, _share in ranked[:count]]


def corporate_building_id(corp_id: str, sector_id: str) -> str:
    return f"corp_{corp_id}_{sector_id}_office"


def upsert_by_id(entries: list, record: dict) -> None:
    record_id = str(record.get("id", ""))
    for index, entry in enumerate(entries):
        if isinstance(entry, dict) and str(entry.get("id", "")) == record_id:
            entries[index] = record
            return
    entries.append(record)


def upsert_route(routes: list, record: dict) -> None:
    route_id = str(record.get("id", ""))
    for index, entry in enumerate(routes):
        if isinstance(entry, dict) and str(entry.get("id", "")) == route_id:
            routes[index] = record
            return
    routes.append(record)


def validate_spec(spec: dict, catalog_dir: Path, replace: bool) -> list[str]:
    errors: list[str] = []
    sector_id = str(spec.get("id", ""))
    if not sector_id:
        errors.append("spec: missing id")
        return errors

    commodities = index_by_id(load_array(catalog_dir / "commodities.json"))
    sectors = index_by_id(load_array(catalog_dir / "sectors.json"))
    worlds = load_object(catalog_dir / "worlds.json")

    if sector_id in sectors and not replace:
        errors.append(f"spec: sector id '{sector_id}' already exists (use --replace)")

    economy = spec.get("economy", spec)
    for key in ("produce", "consume"):
        block = economy.get(key, {})
        if not isinstance(block, dict):
            errors.append(f"spec: economy.{key} must be an object")
            continue
        for commodity_id in block.keys():
            if str(commodity_id) not in commodities:
                errors.append(f"spec: unknown commodity '{commodity_id}' in {key}")

    routes_spec = spec.get("routes", [])
    if not isinstance(routes_spec, list) or not routes_spec:
        errors.append("spec: routes must be a non-empty array")
    else:
        for route in routes_spec:
            if not isinstance(route, dict):
                continue
            peer = str(route.get("b", ""))
            if not peer:
                errors.append("spec: route missing peer sector id 'b'")
            elif peer not in sectors and peer != sector_id:
                errors.append(f"spec: unknown route peer sector '{peer}'")

    orbitals = spec.get("orbitals", [])
    if isinstance(orbitals, list):
        for sprite in orbitals:
            sprite_path = str(sprite)
            if sprite_path.startswith("res://assets/world/orbitals/"):
                name = sprite_path.split("/")[-1]
                if not (ORBITAL_SPRITE_DIR / name).exists():
                    errors.append(f"spec: orbital sprite not found '{name}'")

    extra_buildings = spec.get("extra_buildings", [])
    if isinstance(extra_buildings, list):
        buildings = index_by_id(load_array(catalog_dir / "buildings.json"))
        for building_id in extra_buildings:
            if str(building_id) not in buildings:
                errors.append(f"spec: unknown extra_building '{building_id}'")

    if sector_id in worlds and not replace:
        errors.append(f"spec: worlds.json already has key '{sector_id}' (use --replace)")

    corporations = index_by_id(load_array(catalog_dir / "corporations.json"))
    anchors = spec.get("presence_anchors", {})
    if not isinstance(anchors, dict):
        errors.append("spec: presence_anchors must be an object")
    else:
        for corp_id, weight in anchors.items():
            if str(corp_id) not in corporations:
                errors.append(f"spec: unknown presence anchor '{corp_id}'")
            elif isinstance(weight, bool) or not isinstance(weight, (int, float)) or weight < 0:
                errors.append(f"spec: presence anchor '{corp_id}' must be a non-negative number")

    peacekeeping = spec.get("peacekeeping", "")
    if not isinstance(peacekeeping, str):
        errors.append("spec: peacekeeping must be a string")

    return errors


def build_bundle(spec: dict, corporations: list) -> dict:
    sector_id = str(spec["id"])
    name = str(spec["name"])
    planet_name = str(spec.get("planet_name", name))
    orbit_name = str(spec.get("orbit_name", f"{planet_name} high orbit"))
    objective = str(spec.get("objective", f"Explore {orbit_name}"))

    planet = spec.get("planet", {})
    sprite = str(planet.get("sprite", DEFAULT_PLANET_SPRITE))
    diameter = int(planet.get("diameter", 2000))
    modulate = str(planet.get("modulate", "#ffffff"))

    habitat_spec = spec.get("habitat", {})
    habitat_name = str(habitat_spec.get("name", f"{planet_name} Habitat"))
    habitat_desc = str(
        habitat_spec.get(
            "description",
            f"Orbital city hub above {planet_name}.",
        )
    )
    habitat_short = str(habitat_spec.get("short_desc", habitat_desc))
    habitat_sprite = str(habitat_spec.get("sprite", DEFAULT_HABITAT_SPRITE))

    economy = spec.get("economy", spec)
    tier = str(economy.get("tier", "mid"))
    wealth = float(economy.get("wealth", 1.0))
    produce = dict(economy.get("produce", {}))
    consume = dict(economy.get("consume", {}))

    terminal_id = f"{sector_id}_habitat_terminal"
    shipyard_id = f"{sector_id}_shipyard"
    exchange_id = f"{sector_id}_exchange"
    habitat_id = f"{sector_id}_habitat"
    habitat_art = str(
        habitat_spec.get("art", f"res://assets/ui/locations/{habitat_id}.png")
    )
    dock_interactable_id = f"{sector_id}_habitat"
    gate_interactable_id = f"{sector_id}_jump_gate"

    extra_buildings = [
        str(b) for b in spec.get("extra_buildings", []) if str(b)
    ]
    corp_ids = sorted(
        str(corp.get("id", ""))
        for corp in corporations
        if isinstance(corp, dict) and str(corp.get("id", ""))
    )
    corp_names = {
        str(corp.get("id", "")): str(corp.get("name", corp.get("id", "")))
        for corp in corporations
        if isinstance(corp, dict) and corp.get("id")
    }
    raw_anchors = spec.get("presence_anchors", {})
    anchors = {
        str(corp_id): float(weight)
        for corp_id, weight in raw_anchors.items()
    } if isinstance(raw_anchors, dict) else {}
    presence = build_sector_presence(corp_ids, sector_id, anchors)

    scan_buildings: list[dict] = []
    peacekeeping_name = str(spec.get("peacekeeping", "")).strip()
    if peacekeeping_name:
        peace_id = f"{sector_id}_peaceforce"
        scan_buildings.append(
            {
                "id": peace_id,
                "name": peacekeeping_name,
                "type": "peacekeeping",
                "kind": "office",
                "description": (
                    f"{peacekeeping_name} liaison office posting reconnaissance "
                    "and survey charters."
                ),
                "short_desc": "System peacekeeping charter desk.",
                "art": f"res://assets/ui/locations/{peace_id}.png",
            }
        )
        for corp_id in top_corporation_ids(presence, corporate_office_count(sector_id)):
            office_id = corporate_building_id(corp_id, sector_id)
            cname = corp_names.get(corp_id, corp_id)
            scan_buildings.append(
                {
                    "id": office_id,
                    "name": f"{cname} Office",
                    "type": "corporate_office",
                    "kind": "office",
                    "corporation_id": corp_id,
                    "description": f"Corporate liaison desk for {cname}.",
                    "short_desc": f"{cname} charter desk.",
                    "art": f"res://assets/ui/locations/{office_id}.png",
                }
            )

    scan_ids = [str(building["id"]) for building in scan_buildings]
    building_ids = [terminal_id, *extra_buildings, shipyard_id, exchange_id, *scan_ids]

    sector = {
        "id": sector_id,
        "name": name,
        "orbit_name": orbit_name,
        "planet_name": planet_name,
        "star_system": str(spec["star_system"]),
        "classification": str(spec["classification"]),
        "gravity": float(spec.get("gravity", 1.0)),
        "population_billions": float(spec["population_billions"]),
        "ocean_coverage": float(spec.get("ocean_coverage", 0.5)),
        "climate": str(spec["climate"]),
        "city_malls": list(spec.get("city_malls", [])),
        "play_bounds": int(spec.get("play_bounds", 8000)),
        "objective": objective,
        "mappings": [],
    }

    orbitals_list: list[dict] = [
        {
            "id": f"{sector_id}_habitat_obj",
            "kind": "habitat",
            "label": habitat_name,
            "interactable": dock_interactable_id,
            "sprite": habitat_sprite,
        }
    ]
    if modulate.lower() not in ("#ffffff", "#fff"):
        orbitals_list[0]["modulate"] = modulate

    for index, sprite_path in enumerate(spec.get("orbitals", []), start=1):
        orbitals_list.append(
            {
                "id": f"{sector_id}_orbital_{index}",
                "kind": "orbital",
                "sprite": str(sprite_path),
            }
        )

    world = {
        "planet": {
            "sprite": sprite,
            "diameter": diameter,
            "modulate": modulate,
        },
        "orbital_ring": {
            "radius": 1600,
            "period_seconds": 720,
            "orbitals": orbitals_list,
        },
        "jump_gate": {
            "id": f"{sector_id}_jump_gate_obj",
            "label": f"{planet_name} Jump Gate",
            "interactable": gate_interactable_id,
            "radius": 5400,
        },
    }

    economy_record = {
        "id": sector_id,
        "tier": tier,
        "wealth": wealth,
        "produce": produce,
        "consume": consume,
    }

    habitat = {
        "id": habitat_id,
        "sector_id": sector_id,
        "name": habitat_name,
        "type": "habitat",
        "description": habitat_desc,
        "short_desc": habitat_short,
        "art": habitat_art,
        "default_building": terminal_id,
        "buildings": building_ids,
    }

    terminal = {
        "id": terminal_id,
        "name": f"{habitat_name} Terminal",
        "type": "terminal",
        "kind": "terminal",
        "description": habitat_desc,
        "short_desc": habitat_short,
        "art": f"res://assets/ui/locations/{terminal_id}.png",
    }

    shipyard = {
        "id": shipyard_id,
        "name": f"{habitat_name} Shipyard",
        "type": "shipyard",
        "kind": "workshop",
        "description": (
            f"Outfitting bays for installing systems on ships docked at {habitat_name}."
        ),
        "short_desc": f"Outfitting bays at {habitat_name}.",
        "art": f"res://assets/ui/locations/{shipyard_id}.png",
        "services": ["assembly", "parts"],
    }

    exchange = {
        "id": exchange_id,
        "name": f"{planet_name} Exchange",
        "type": "market",
        "kind": "merchant",
        "description": f"Automated commodity exchange for {planet_name} orbital contracts.",
        "short_desc": f"Automated commodity exchange for {planet_name} orbital contracts.",
        "art": f"res://assets/ui/locations/{exchange_id}.png",
    }

    dock_interactable = {
        "id": dock_interactable_id,
        "title": habitat_name,
        "inspect_text": f"{habitat_short} Docking lanes are open.",
        "kind": "dock",
        "dock_location_id": habitat_id,
    }

    gate_interactable = {
        "id": gate_interactable_id,
        "title": f"{planet_name} Jump Gate",
        "inspect_text": "Unspace translation ring. Select a known route to translate.",
        "kind": "translate",
    }

    routes: list[dict] = []
    for route_spec in spec.get("routes", []):
        if not isinstance(route_spec, dict):
            continue
        peer = str(route_spec["b"])
        friction = int(route_spec["friction"])
        n = int(route_spec.get("n", 4))
        route_id = f"{peer}_{sector_id}"
        routes.append(
            {
                "id": route_id,
                "a": peer,
                "b": sector_id,
                "friction": friction,
                "translations": [
                    {
                        "n": n,
                        "solution_ab": int(route_spec["solution_ab"]),
                        "solution_ba": int(route_spec["solution_ba"]),
                    }
                ],
            }
        )

    traffic_override = spec.get("traffic_role_weights")

    return {
        "sector": sector,
        "world": world,
        "economy": economy_record,
        "habitat": habitat,
        "buildings": [terminal, shipyard, exchange, *scan_buildings],
        "presence": presence,
        "interactables": [dock_interactable, gate_interactable],
        "routes": routes,
        "traffic_override": traffic_override,
    }


def apply_bundle(catalog_dir: Path, bundle: dict, replace: bool) -> None:
    sector_id = str(bundle["sector"]["id"])

    sectors_path = catalog_dir / "sectors.json"
    sectors = load_array(sectors_path)
    upsert_by_id(sectors, bundle["sector"])
    write_json(sectors_path, sectors)

    worlds_path = catalog_dir / "worlds.json"
    worlds = load_object(worlds_path)
    if sector_id in worlds and not replace:
        raise ValueError(f"worlds.json already contains '{sector_id}'")
    worlds[sector_id] = bundle["world"]
    write_json(worlds_path, worlds)

    economies_path = catalog_dir / "economies.json"
    economies = load_array(economies_path)
    upsert_by_id(economies, bundle["economy"])
    write_json(economies_path, economies)

    habitats_path = catalog_dir / "habitats.json"
    habitats = load_array(habitats_path)
    upsert_by_id(habitats, bundle["habitat"])
    write_json(habitats_path, habitats)

    buildings_path = catalog_dir / "buildings.json"
    buildings = load_array(buildings_path)
    for building in bundle["buildings"]:
        upsert_by_id(buildings, building)
    write_json(buildings_path, buildings)

    interactables_path = catalog_dir / "interactables.json"
    interactables = load_array(interactables_path)
    for interactable in bundle["interactables"]:
        upsert_by_id(interactables, interactable)
    write_json(interactables_path, interactables)

    routes_path = catalog_dir / "routes.json"
    routes = load_array(routes_path)
    for route in bundle["routes"]:
        upsert_route(routes, route)
    write_json(routes_path, routes)

    traffic_override = bundle.get("traffic_override")
    if isinstance(traffic_override, dict) and traffic_override:
        traffic_path = catalog_dir / "traffic.json"
        traffic = load_object(traffic_path)
        overrides = traffic.setdefault("sector_overrides", {})
        if not isinstance(overrides, dict):
            overrides = {}
            traffic["sector_overrides"] = overrides
        overrides[sector_id] = {"role_weights": dict(traffic_override)}
        write_json(traffic_path, traffic)

    presence_path = catalog_dir / "corporate_presence.json"
    presence = load_object(presence_path)
    presence[sector_id] = bundle["presence"]
    write_json_matching(presence_path, presence)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, required=True, help="Sector bundle spec JSON")
    parser.add_argument(
        "--catalog",
        type=Path,
        default=CATALOG,
        help="Catalog directory (default: data/catalog)",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Replace existing records for this sector id",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print bundle without writing files",
    )
    args = parser.parse_args()

    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    errors = validate_spec(spec, args.catalog, args.replace)
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    corporations = load_array(args.catalog / "corporations.json")
    bundle = build_bundle(spec, corporations)
    if args.dry_run:
        print(json.dumps(bundle, indent=2))
        return 0

    apply_bundle(args.catalog, bundle, args.replace)
    print(f"OK: sector bundle applied for '{bundle['sector']['id']}'.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
