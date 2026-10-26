#!/usr/bin/env python3
"""Apply corporate headquarters layout from setting doc to catalog JSON."""

from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"

SECTOR_HABITAT = {
    "proxima": "proxima_habitat",
    "tycho": "tycho_habitat",
    "bela": "bela_orbital_habitat",
    "irasia": "irasia_habitat",
    "tokirev": "tokirev_habitat",
    "fennet": "fennet_habitat",
    "fortuna": "fortuna_habitat",
    "new_carthage": "new_carthage_habitat",
    "horizon": "horizon_habitat",
    "titania": "titania_habitat",
    "pelagos": "concordia_habitat",
    "regulus_belt": "regulus_belt_habitat",
    "pelagos_belt": "pelagos_belt_habitat",
}

# corp_id -> (placement, sector_id, location_id or None for planet, optional building_id for retitle/outlying)
HQ_SPEC: dict[str, tuple] = {
    "galactic_outcomes": ("orbital", "tycho", "sta_galactic_outcomes_tycho", "tycho_orbital_1"),
    "karaquazen": ("habitat", "bela", "bela_orbital_habitat", "corp_karaquazen_bela_office"),
    "himalaya_triad": ("habitat", "horizon", "horizon_habitat", None),
    "microdonald": ("planet", "proxima", None),
    "pararamcovidia": ("habitat", "proxima", "proxima_habitat", None),
    "grc": ("orbital", "fortuna", "sta_grc_fortuna", "fortuna_orbital_1"),
    "creus": ("orbital", "proxima", "sta_creus_proxima", "proxima_orbital_1"),
    "holt_winters": ("habitat", "tokirev", "tokirev_habitat", None),
    "tukey": ("planet", "tokirev", None),
    "snedecorp": ("orbital", "proxima", "sta_snedecorp_proxima", "proxima_orbital_2"),
    "oklahoma_combine": ("planet", "fennet", None),
    "sakuraya_shinise": ("planet", "proxima", None),
    "cult_of_apex": ("orbital", "titania", "sta_cult_of_apex_titania", "titania_orbital_1"),
    "carthage_mercantile": (
        "habitat",
        "new_carthage",
        "new_carthage_habitat",
        "corp_carthage_mercantile_new_carthage_office",
    ),
    "pacific_triad": ("planet", "horizon", None),
    "monday": ("habitat", "proxima", "proxima_habitat", None),
    "house_of_roth": ("habitat", "fortuna", "fortuna_habitat", "corp_house_of_roth_fortuna_office"),
    "seven_bells": ("planet", "irasia", None),
    "general_industrial": ("orbital", "tycho", "sta_general_industrial_tycho", "tycho_orbital_2"),
    "morrow_and_sons": ("orbital", "proxima", "sta_morrow_and_sons_proxima", "proxima_orbital_3"),
    "octagon": ("orbital", "fortuna", "sta_octagon_fortuna", "fortuna_orbital_2"),
    "meridian": ("habitat", "new_carthage", "new_carthage_habitat", None),
    "crown_and_anchor": (
        "orbital",
        "new_carthage",
        "sta_crown_and_anchor_new_carthage",
        "new_carthage_orbital_1",
    ),
    "universal_house": ("habitat", "bela", "bela_orbital_habitat", None),
    "evergreen": ("planet", "fennet", None),
    "atlas_concern": ("outlying", "regulus_belt", "regulus_belt_habitat", None),
    "hanseatic_guild": ("planet", "new_carthage", None),
    "continuity_foundation": ("habitat", "proxima", "proxima_habitat", None),
    "four_rivers_zaibatsu": ("planet", "tokirev", None),
    "chettiar": ("planet", "fortuna", None),
    "andean_consolidated": ("planet", "fennet", None),
    "dar_al_nour": ("habitat", "horizon", "horizon_habitat", None),
    "guangzhou_mercantile": ("planet", "new_carthage", None),
    "mercury_communications": (
        "orbital",
        "proxima",
        "sta_mercury_communications_proxima",
        "proxima_orbital_4",
    ),
    "orion_aerospace": ("orbital", "irasia", "sta_orion_aerospace_irasia", "irasia_orbital_1"),
    "greenfields": ("planet", "horizon", None),
    "biogenesis": ("habitat", "irasia", "irasia_habitat", None),
    "liveworlds": ("planet", "bela", None),
    "chimera": ("orbital", "titania", "sta_chimera_titania", "titania_orbital_2"),
    "praetorium": ("habitat", "proxima", "proxima_habitat", None),
    "terra_nova": ("orbital", "pelagos", "sta_terra_nova_pelagos", "pelagos_orbital_1"),
    "orion_spur": ("habitat", "pelagos", "concordia_habitat", None),
    "deepspace": ("outlying", "pelagos_belt", "pelagos_belt_habitat", None),
}

ORBITAL_LABELS = {
    ("tycho", "tycho_orbital_1"): "Galactic Outcomes Headquarters",
    ("tycho", "tycho_orbital_2"): "General Industrial Headquarters",
    ("proxima", "proxima_orbital_1"): "Creus Corporation Headquarters",
    ("proxima", "proxima_orbital_2"): "SnedeCorp Headquarters",
    ("proxima", "proxima_orbital_3"): "Morrow & Sons Headquarters",
    ("proxima", "proxima_orbital_4"): "Mercury Communications Headquarters",
    ("fortuna", "fortuna_orbital_1"): "GRC Inc Headquarters",
    ("fortuna", "fortuna_orbital_2"): "The Octagon Headquarters",
    ("titania", "titania_orbital_1"): "Fellowship of Apex Headquarters",
    ("titania", "titania_orbital_2"): "Chimera Corporation Headquarters",
    ("new_carthage", "new_carthage_orbital_1"): "Crown & Anchor Headquarters",
    ("irasia", "irasia_orbital_1"): "Orion Aerospace Headquarters",
    ("pelagos", "pelagos_orbital_1"): "Terra Nova Headquarters",
}


def load_json(path: Path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t", ensure_ascii=False)
        f.write("\n")


def corp_name(corporations: list, corp_id: str) -> str:
    for c in corporations:
        if c.get("id") == corp_id:
            return str(c.get("name", corp_id))
    return corp_id


def hq_building_id(corp_id: str, sector_id: str) -> str:
    return f"corp_hq_{corp_id}_{sector_id}"


def sta_terminal_id(sta_id: str) -> str:
    return f"{sta_id}_terminal"


def sta_hq_id(sta_id: str) -> str:
    return f"{sta_id}_hq"


def sta_dock_id(sta_id: str) -> str:
    return f"{sta_id}_dock"


def make_corp_office(
    building_id: str,
    corp_id: str,
    cname: str,
    *,
    headquarters: bool = False,
) -> dict:
    art = f"res://assets/ui/locations/{building_id}.png"
    suffix = "Headquarters" if headquarters else "Office"
    return {
        "art": art,
        "corporation_id": corp_id,
        "description": f"Corporate headquarters for {cname}."
        if headquarters
        else f"Corporate liaison desk for {cname}.",
        "headquarters": headquarters,
        "id": building_id,
        "kind": "office",
        "name": f"{cname} {suffix}",
        "short_desc": f"{cname} charter desk.",
        "type": "corporate_office",
    }


def make_terminal(building_id: str, station_name: str) -> dict:
    art = f"res://assets/ui/locations/{building_id}.png"
    return {
        "art": art,
        "description": f"Docking terminal at {station_name}. Ship administration and launch.",
        "id": building_id,
        "kind": "terminal",
        "name": f"{station_name} Terminal",
        "short_desc": "Docking terminal.",
        "type": "terminal",
    }


def make_station_habitat(
    sta_id: str,
    sector_id: str,
    station_name: str,
    terminal_id: str,
    hq_id: str,
) -> dict:
    art = f"res://assets/ui/locations/{sta_id}.png"
    return {
        "art": art,
        "buildings": [terminal_id, hq_id],
        "default_building": terminal_id,
        "description": f"Dedicated corporate orbital above the sector. {station_name} maintains its own docks.",
        "id": sta_id,
        "name": station_name,
        "sector_id": sector_id,
        "short_desc": "Corporate headquarters orbital.",
        "type": "station",
    }


def add_hq_to_corporations(corporations: list) -> bool:
    by_id = {c["id"]: c for c in corporations}
    changed = False
    for corp_id, spec in HQ_SPEC.items():
        if corp_id not in by_id:
            raise SystemExit(f"unknown corp {corp_id}")
        if "hq" in by_id[corp_id]:
            continue
        placement = spec[0]
        sector_id = spec[1]
        location_id = spec[2] if len(spec) > 2 else None
        hq: dict = {"placement": placement, "sector_id": sector_id}
        if placement != "planet" and location_id:
            hq["location_id"] = location_id
        by_id[corp_id]["hq"] = hq
        changed = True
    return changed


def main() -> int:
    corporations = load_json(CATALOG / "corporations.json")
    buildings = load_json(CATALOG / "buildings.json")
    habitats = load_json(CATALOG / "habitats.json")
    interactables = load_json(CATALOG / "interactables.json")
    worlds = load_json(CATALOG / "worlds.json")
    sectors = load_json(CATALOG / "sectors.json")
    routes = load_json(CATALOG / "routes.json")
    economies = load_json(CATALOG / "economies.json")
    presence = load_json(CATALOG / "corporate_presence.json")

    building_by_id = {b["id"]: b for b in buildings}
    habitat_by_id = {h["id"]: h for h in habitats}
    interactable_ids = {str(i.get("id", "")) for i in interactables if isinstance(i, dict)}

    corps_dirty = add_hq_to_corporations(corporations)
    buildings_dirty = False
    habitats_dirty = False
    interactables_dirty = False
    worlds_dirty = False
    sectors_dirty = False
    routes_dirty = False
    economies_dirty = False
    presence_dirty = False

    new_buildings: list[dict] = []
    new_habitats: list[dict] = []
    new_interactables: list[dict] = []

    for corp_id, spec in HQ_SPEC.items():
        placement, sector_id = spec[0], spec[1]
        location_id = spec[2] if len(spec) > 2 else None
        retitle_id = spec[3] if len(spec) > 3 else None
        cname = corp_name(corporations, corp_id)

        if placement == "planet":
            continue

        if placement == "orbital":
            assert location_id and retitle_id
            sta_id = location_id
            term_id = sta_terminal_id(sta_id)
            hq_id = sta_hq_id(sta_id)
            dock_id = sta_dock_id(sta_id)
            label = ORBITAL_LABELS.get((sector_id, retitle_id), f"{cname} Headquarters")
            station_name = label.replace(" Headquarters", "")
            if term_id not in building_by_id:
                new_buildings.append(make_terminal(term_id, station_name))
            if hq_id not in building_by_id:
                new_buildings.append(make_corp_office(hq_id, corp_id, cname, headquarters=True))
            if sta_id not in habitat_by_id:
                new_habitats.append(make_station_habitat(sta_id, sector_id, station_name, term_id, hq_id))
            if dock_id not in interactable_ids:
                new_interactables.append(
                    {
                        "id": dock_id,
                        "title": label,
                        "inspect_text": f"{label}. Docking lanes are open on transponder.",
                        "kind": "dock",
                        "dock_location_id": sta_id,
                    }
                )
                interactable_ids.add(dock_id)
            continue

        if placement in ("habitat", "outlying"):
            assert location_id
            hab = habitat_by_id.get(location_id)
            if hab is None and location_id == "pelagos_belt_habitat":
                continue
            if retitle_id:
                if retitle_id not in building_by_id:
                    raise SystemExit(f"missing retitle building {retitle_id}")
                continue
            bid = hq_building_id(corp_id, sector_id)
            if bid not in building_by_id:
                new_buildings.append(make_corp_office(bid, corp_id, cname, headquarters=True))
            if hab is not None and bid not in hab.get("buildings", []):
                hab.setdefault("buildings", []).append(bid)
                habitats_dirty = True

    # Pelagos belt sector bundle
    if "pelagos_belt" not in {s["id"] for s in sectors}:
        sectors_dirty = True
        sectors.append(
            {
                "id": "pelagos_belt",
                "name": "Pelagos Belt Station Sector",
                "orbit_name": "Pelagos Belt Station near orbit",
                "star_system": "Kepler-16",
                "description": "Asteroid belt in the Kepler-16 system beyond Pelagos. Mining convoys and cooperative haulage share the lanes.",
                "gravity": 0.18,
                "population_billions": 0.35,
                "play_bounds": 8000,
                "objective": "Explore Pelagos Belt Station near orbit",
                "mappings": [],
                "neighborhood": {
                    "magnetic_surface": 1.0,
                    "magnetic_fluctuation": 0.0,
                    "radiant": 1.0,
                    "radiant_fluctuation": 0.3,
                    "charged_particle": 1.0,
                    "charged_particle_fluctuation": 0.0,
                },
            }
        )

    if "pelagos_belt" not in worlds:
        worlds_dirty = True
        worlds["pelagos_belt"] = copy.deepcopy(worlds["regulus_belt"])
        worlds["pelagos_belt"]["translation_beacon"] = {
            "id": "pelagos_belt_beacon_obj",
            "label": "Pelagos Belt Station Translation Beacon",
            "interactable": "pelagos_belt_jump_gate",
            "destination": "pelagos",
            "radius": 5400,
        }
        ring = worlds["pelagos_belt"]["orbital_ring"]
        ring["orbitals"][0]["id"] = "pelagos_belt_habitat_obj"
        ring["orbitals"][0]["label"] = "Pelagos Belt Station"
        ring["orbitals"][0]["interactable"] = "pelagos_belt_habitat"
        ring["orbitals"][1]["id"] = "pelagos_belt_orbital_1"
        ring["orbitals"][2]["id"] = "pelagos_belt_orbital_2"
        entities = worlds["pelagos_belt"].get("entities", [])
        for i, ent in enumerate(entities):
            if isinstance(ent, dict) and "id" in ent:
                ent["id"] = str(ent["id"]).replace("regulus_belt", "pelagos_belt")
        worlds["pelagos_belt"]["star"] = {"temperature_k": 4500, "luminosity": 1.0}

    route_ids = {r["id"] for r in routes}
    if "pelagos_pelagos_belt" not in route_ids:
        routes_dirty = True
        routes.append(
            {
                "id": "pelagos_pelagos_belt",
                "a": "pelagos",
                "b": "pelagos_belt",
                "friction": 5,
                "translations": [{"n": 4, "solution_ab": 48117, "solution_ba": -48118}],
            }
        )

    if "pelagos_belt" not in {e["id"] for e in economies}:
        economies_dirty = True
        belt_econ = copy.deepcopy(next(e for e in economies if e["id"] == "regulus_belt"))
        belt_econ["id"] = "pelagos_belt"
        economies.append(belt_econ)

    if "pelagos_belt" not in presence:
        presence_dirty = True
        belt_pres = copy.deepcopy(presence["regulus_belt"])
        belt_pres["deepspace"] = 18.0
        total = sum(belt_pres.values())
        belt_pres = {k: round(v / total * 100.0, 2) for k, v in belt_pres.items()}
        drift = 100.0 - sum(belt_pres.values())
        belt_pres["deepspace"] = round(belt_pres["deepspace"] + drift, 2)
        presence["pelagos_belt"] = belt_pres

    if "pelagos_belt_habitat" not in habitat_by_id:
        habitats_dirty = True
        pel_term = "pelagos_belt_terminal"
        pel_ex = "pelagos_belt_exchange"
        dsc_hq = hq_building_id("deepspace", "pelagos_belt")
        if pel_term not in building_by_id:
            new_buildings.append(
                {
                    "art": f"res://assets/ui/locations/{pel_term}.png",
                    "description": "Customs and convoy scheduling for Pelagos Belt Station.",
                    "id": pel_term,
                    "kind": "terminal",
                    "name": "Pelagos Belt Terminal",
                    "short_desc": "Terminal for Pelagos Belt traffic.",
                    "type": "terminal",
                }
            )
        if pel_ex not in building_by_id:
            new_buildings.append(
                {
                    "art": f"res://assets/ui/locations/{pel_ex}.png",
                    "description": "Commodity exchange for Pelagos Belt contracts and hub supply runs.",
                    "id": pel_ex,
                    "kind": "merchant",
                    "name": "Pelagos Belt Exchange",
                    "short_desc": "Exchange at Pelagos Belt Station.",
                    "type": "market",
                }
            )
        if dsc_hq not in building_by_id:
            new_buildings.append(
                make_corp_office(
                    dsc_hq,
                    "deepspace",
                    corp_name(corporations, "deepspace"),
                    headquarters=True,
                )
            )
        habitats.append(
            {
                "art": "res://assets/ui/locations/pelagos_belt_habitat.png",
                "buildings": [pel_term, pel_ex, dsc_hq],
                "default_building": pel_term,
                "description": "Central habitat for the asteroid belt beyond Pelagos. Cooperative haulage and mining convoys share the lanes.",
                "id": "pelagos_belt_habitat",
                "name": "Pelagos Belt Station",
                "sector_id": "pelagos_belt",
                "short_desc": "Belt mining habitat beyond Pelagos.",
                "type": "habitat",
            }
        )
        if "pelagos_belt_habitat" not in interactable_ids:
            interactables_dirty = True
            new_interactables.extend(
                [
                    {
                        "id": "pelagos_belt_habitat",
                        "title": "Pelagos Belt Station",
                        "inspect_text": "Belt mining habitat. Docking lanes are open; cooperative traffic fills the approaches.",
                        "kind": "dock",
                        "dock_location_id": "pelagos_belt_habitat",
                    },
                    {
                        "id": "pelagos_belt_jump_gate",
                        "title": "Pelagos Belt Translation Beacon",
                        "inspect_text": "Translation beacon back toward Pelagos near orbit.",
                        "kind": "translate",
                    },
                ]
            )

    pending_ids = {str(b.get("id", "")) for b in new_buildings}
    atlas_hq = hq_building_id("atlas_concern", "regulus_belt")
    if atlas_hq not in building_by_id and atlas_hq not in pending_ids:
        new_buildings.append(
            make_corp_office(atlas_hq, "atlas_concern", corp_name(corporations, "atlas_concern"), headquarters=True)
        )
    rb = habitat_by_id["regulus_belt_habitat"]
    if atlas_hq not in rb.get("buildings", []):
        rb.setdefault("buildings", []).append(atlas_hq)
        habitats_dirty = True

    # Wire orbital interactables in worlds
    sta_by_orbital: dict[tuple[str, str], str] = {}
    for corp_id, spec in HQ_SPEC.items():
        if spec[0] != "orbital":
            continue
        sector_id, sta_id, orbital_id = spec[1], spec[2], spec[3]
        sta_by_orbital[(sector_id, orbital_id)] = sta_dock_id(sta_id)

    for sector_id, world in worlds.items():
        ring = world.get("orbital_ring")
        if not isinstance(ring, dict):
            continue
        orbitals = ring.get("orbitals", [])
        if not isinstance(orbitals, list):
            continue
        for orb in orbitals:
            if not isinstance(orb, dict):
                continue
            oid = str(orb.get("id", ""))
            key = (sector_id, oid)
            if key in sta_by_orbital:
                if str(orb.get("interactable", "")).strip():
                    continue
                dock_id = sta_by_orbital[key]
                label = ORBITAL_LABELS.get(key, "Corporate Headquarters")
                orb["label"] = label
                orb["interactable"] = dock_id
                orb["kind"] = "orbital"
                worlds_dirty = True

    if new_buildings:
        buildings.extend(new_buildings)
        buildings_dirty = True
    if new_habitats:
        habitats.extend(new_habitats)
        habitats_dirty = True
    if new_interactables:
        interactables.extend(new_interactables)
        interactables_dirty = True

    if corps_dirty:
        save_json(CATALOG / "corporations.json", corporations)
    if buildings_dirty:
        save_json(CATALOG / "buildings.json", buildings)
    if habitats_dirty:
        save_json(CATALOG / "habitats.json", habitats)
    if interactables_dirty:
        save_json(CATALOG / "interactables.json", interactables)
    if worlds_dirty:
        save_json(CATALOG / "worlds.json", worlds)
    if sectors_dirty:
        save_json(CATALOG / "sectors.json", sectors)
    if routes_dirty:
        save_json(CATALOG / "routes.json", routes)
    if economies_dirty:
        save_json(CATALOG / "economies.json", economies)
    if presence_dirty:
        save_json(CATALOG / "corporate_presence.json", presence)

    print(
        f"Added {len(new_buildings)} buildings, {len(new_habitats)} stations, "
        f"{len(new_interactables)} interactables."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
