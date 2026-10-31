#!/usr/bin/env python3
"""Validate cross-catalog referential integrity."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import load_modules
from validate_sector_completeness import check as check_sector_completeness

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"


def _load_module_rules() -> dict:
    path = ROOT / "data" / "validation" / "module_rules.json"
    with path.open(encoding="utf-8") as handle:
        loaded = json.load(handle)
    if not isinstance(loaded, dict):
        raise SystemExit("module_rules.json must be an object")
    return loaded


MODULE_RULES = _load_module_rules()


def _rule_names(group: str, key: str) -> set[str]:
    rows = MODULE_RULES.get(group, {}).get(key, [])
    if not isinstance(rows, list):
        raise SystemExit(f"module_rules.json {group}.{key} must be an array")
    return {str(row) for row in rows}


POWER_PLANT_MAKERS = _rule_names("makers", "power")
COMPUTE_CORE_MAKERS = _rule_names("makers", "computer")
LIFE_SUPPORT_MAKERS = _rule_names("makers", "life_support")
CARGO_MAKERS = _rule_names("makers", "cargo")
PROPULSION_MAKERS = _rule_names("makers", "propulsion")
WEAPON_MAKERS = _rule_names("makers", "weapon")
ARMOUR_SHIELD_MAKERS = _rule_names("makers", "armour_shield")
HYPERDRIVE_MAKERS = _rule_names("makers", "hyperdrive")
RETIRED_POWER_IDS = _rule_names("retired_ids", "power")
RETIRED_COMPUTER_IDS = _rule_names("retired_ids", "computer")
RETIRED_LIFE_SUPPORT_IDS = _rule_names("retired_ids", "life_support")
RETIRED_SENSOR_IDS = _rule_names("retired_ids", "sensor")
RETIRED_PROPULSION_IDS = _rule_names("retired_ids", "propulsion")
RETIRED_WEAPON_IDS = _rule_names("retired_ids", "weapon")
BANNED_PROPULSION_MAKERS = _rule_names("banned_makers", "propulsion")
BANNED_WEAPON_MAKERS = _rule_names("banned_makers", "weapon")
BANNED_ARMOUR_MAKERS = _rule_names("banned_makers", "armour")


POWER_PLANT_TYPES = {"fission", "fusion", "radioisotope"}
COMPUTE_CORE_TYPES = {"silicon", "photon", "quantum"}
LIFE_SUPPORT_FLAGS = {"ls_comfort", "ls_luxury", "ls_habitat"}

CARGO_CAPABILITY_FLAGS = {
    "life_support_integrated",
    "refrigerated",
    "compute_integrated",
    "biohazard",
    "secure_cargo",
    "military_grade",
}
CARGO_SKU_FLOOR = 18
# SKU counts are floors, not exact expectations. Adding content must never fail validation;
# these only catch accidental bulk deletion. Do not convert them back to equality checks.
SENSOR_SKU_FLOOR = 8
LIFE_SUPPORT_SKU_FLOOR = 35
TRANSPORT_VOLUME_PER_CREW = {"spartan": 2.5, "comfort": 5.0, "luxury": 7.0}
HABITAT_VOLUME_PER_CREW = {"spartan": 8.0, "comfort": 11.0, "luxury": 14.0}
TRANSPORT_ONE_SEAT_COCKPIT_FLOOR = 4.0

UNSPACE_GST_KEYS = (
    "pulse_min",
    "pulse_max",
    "stretch_min",
    "stretch_max",
    "slip_chance",
    "slip_min",
    "slip_max",
)
UNSPACE_TOPO_KEYS = (
    "seed_salt",
    "fov_vertex_count",
    "scatter_margin",
    "quad_merge_chance",
    "height_scale",
    "vertex_count_min",
    "vertex_count_max",
    "min_dist_factor",
    "default_zoom",
)
UNSPACE_PORTAL_KEYS = (
    "interact_radius",
    "interactable",
    "origin_min_fraction",
    "origin_max_fraction",
    "spawn_separation_fraction",
    "score_spawn_weight",
)
UNSPACE_INHABITANTS_KEYS = (
    "count_min",
    "count_max",
    "speed_min",
    "speed_max",
    "radius_min",
    "radius_max",
    "wander_radius_fraction",
    "min_spawn_dist",
    "fade_band",
    "lobe_count_min",
    "lobe_count_max",
)


def check_unspace_completeness(unspaces: list) -> list[str]:
    errors: list[str] = []
    n_by_depth: dict[int, str] = {}
    for unspace in unspaces:
        if not isinstance(unspace, dict):
            continue
        unspace_id = str(unspace.get("id", ""))
        depth_n = int(unspace.get("n", 0))
        label = unspace_id or "?"
        if depth_n < 4:
            errors.append(f"unspace {label}: n must be >= 4 (got {depth_n})")
        elif depth_n in n_by_depth:
            errors.append(
                f"unspace {label}: duplicate n={depth_n} (also used by {n_by_depth[depth_n]})"
            )
        else:
            n_by_depth[depth_n] = unspace_id

        gst = unspace.get("gst")
        if not isinstance(gst, dict):
            errors.append(f"unspace {label}: missing gst object")
        else:
            for key in UNSPACE_GST_KEYS:
                if key not in gst:
                    errors.append(f"unspace {label}: gst missing '{key}'")

        field = unspace.get("field")
        if not isinstance(field, dict):
            errors.append(f"unspace {label}: missing field object")
            continue

        topo = field.get("topo")
        if not isinstance(topo, dict):
            errors.append(f"unspace {label}: field.topo missing")
        else:
            for key in UNSPACE_TOPO_KEYS:
                if key not in topo:
                    errors.append(f"unspace {label}: field.topo missing '{key}'")

        portal = field.get("portal")
        if not isinstance(portal, dict):
            errors.append(f"unspace {label}: field.portal missing")
        else:
            for key in UNSPACE_PORTAL_KEYS:
                if key not in portal:
                    errors.append(f"unspace {label}: field.portal missing '{key}'")

        inhabitants = field.get("inhabitants")
        if inhabitants is not None:
            if not isinstance(inhabitants, dict):
                errors.append(f"unspace {label}: field.inhabitants must be an object")
            else:
                for key in UNSPACE_INHABITANTS_KEYS:
                    if key not in inhabitants:
                        errors.append(
                            f"unspace {label}: field.inhabitants missing '{key}'"
                        )

    return errors


ALLOWED_WORLD_ENTITY_KINDS = frozenset(
    {"habitat", "jump_gate", "orbital", "debris"}
)


def check_world_entity_kinds(worlds: dict) -> list[str]:
    errors: list[str] = []

    def check_kind(kind: str, label: str) -> None:
        if not kind:
            errors.append(f"{label}: missing kind")
            return
        if kind not in ALLOWED_WORLD_ENTITY_KINDS:
            errors.append(
                f"{label}: unknown world entity kind '{kind}' "
                f"(allowed: {', '.join(sorted(ALLOWED_WORLD_ENTITY_KINDS))})"
            )

    for world_id, world_data in worlds.items():
        if not isinstance(world_data, dict):
            continue
        ring = world_data.get("orbital_ring", {})
        if isinstance(ring, dict):
            orbitals = ring.get("orbitals", [])
            if isinstance(orbitals, list):
                for index, orbital in enumerate(orbitals):
                    if not isinstance(orbital, dict):
                        continue
                    entity_id = str(orbital.get("id", f"index_{index}"))
                    check_kind(
                        str(orbital.get("kind", "")),
                        f"world {world_id} orbital {entity_id}",
                    )
        entities = world_data.get("entities", [])
        if isinstance(entities, list):
            for index, entity in enumerate(entities):
                if not isinstance(entity, dict):
                    continue
                entity_id = str(entity.get("id", f"index_{index}"))
                check_kind(
                    str(entity.get("kind", "")),
                    f"world {world_id} entity {entity_id}",
                )

    return errors


def _is_hex_colour(value: object) -> bool:
    if not isinstance(value, str):
        return False
    text = value.strip()
    if len(text) != 7 or not text.startswith("#"):
        return False
    try:
        int(text[1:], 16)
    except ValueError:
        return False
    return True


def check_parent_body_appearance(label: str, appearance: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(appearance, dict):
        errors.append(f"{label}: appearance must be an object")
        return errors
    appearance_type = str(appearance.get("type", "")).strip()
    allowed_types = ("banded", "gas_giant", "uniform", "mottled", "gradient")
    if appearance_type not in allowed_types:
        errors.append(
            f"{label}: appearance.type must be one of {', '.join(repr(t) for t in allowed_types)}"
        )
        return errors
    atmosphere = appearance.get("atmosphere")
    if isinstance(atmosphere, dict) and atmosphere.get("colours") is not None:
        colours = atmosphere.get("colours")
        min_colours = 1 if appearance_type == "uniform" else 2
        if not isinstance(colours, list) or len(colours) < min_colours or len(colours) > 6:
            errors.append(
                f"{label}: appearance.atmosphere.colours must be an array of "
                f"{min_colours}–6 entries for type '{appearance_type}'"
            )
        else:
            for index, colour in enumerate(colours):
                if not _is_hex_colour(colour):
                    errors.append(f"{label}: appearance.atmosphere.colours[{index}] must be #RRGGBB")
        _check_parent_atmosphere_ranges(label, atmosphere, errors)
    elif appearance_type in ("banded", "gas_giant"):
        for field in ("band_colour_1", "band_colour_2"):
            if not _is_hex_colour(appearance.get(field)):
                errors.append(f"{label}: appearance.{field} must be #RRGGBB")
        turbulence = appearance.get("turbulence")
        if not isinstance(turbulence, (int, float)) or turbulence < 0 or turbulence > 1:
            errors.append(f"{label}: appearance.turbulence must be between 0 and 1")
    else:
        errors.append(
            f"{label}: appearance.atmosphere.colours is required for type '{appearance_type}'"
        )
    orientation = appearance.get("orientation")
    if isinstance(orientation, dict):
        for key, lo, hi in (
            ("axis_inclination_deg", 0, 90),
            ("axis_position_angle_deg", 0, 360),
            ("rotation_phase_deg", 0, 360),
        ):
            if key in orientation:
                val = orientation.get(key)
                if not isinstance(val, (int, float)) or val < lo or val > hi:
                    errors.append(f"{label}: appearance.orientation.{key} must be between {lo} and {hi}")
    if "polar_inclination_deg" in appearance:
        inclination = appearance.get("polar_inclination_deg")
        if not isinstance(inclination, (int, float)) or inclination < 0 or inclination > 90:
            errors.append(f"{label}: appearance.polar_inclination_deg must be between 0 and 90")
    if "orbital_inclination_deg" in appearance:
        inclination = appearance.get("orbital_inclination_deg")
        if not isinstance(inclination, (int, float)) or inclination < 0 or inclination > 90:
            errors.append(f"{label}: appearance.orbital_inclination_deg must be between 0 and 90")
    if "band_meridian_deg" in appearance:
        meridian = appearance.get("band_meridian_deg")
        if not isinstance(meridian, (int, float)) or meridian < 0 or meridian > 360:
            errors.append(f"{label}: appearance.band_meridian_deg must be between 0 and 360")
    return errors


def _check_parent_atmosphere_ranges(label: str, atmosphere: dict, errors: list[str]) -> None:
    ranges = {
        "band_count": (4, 32),
        "band_frequency": (0.5, 4.0),
        "band_width_variation": (0, 1),
        "band_contrast": (0, 1),
        "band_distortion": (0, 1),
        "band_turbulence": (0, 1),
        "band_edge_softness": (0, 1),
        "band_blur": (0, 1),
        "band_fine_detail": (0, 1),
        "turbulence_scale": (0.5, 8.0),
        "turbulence_octaves": (1, 4),
        "polar_blend": (0, 1),
    }
    for key, (lo, hi) in ranges.items():
        if key not in atmosphere:
            continue
        val = atmosphere.get(key)
        if not isinstance(val, (int, float)) or val < lo or val > hi:
            errors.append(f"{label}: appearance.atmosphere.{key} must be between {lo} and {hi}")
    if "polar_colour" in atmosphere and not _is_hex_colour(atmosphere.get("polar_colour")):
        errors.append(f"{label}: appearance.atmosphere.polar_colour must be #RRGGBB")


def check_parent_body_rings(label: str, rings: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(rings, dict):
        errors.append(f"{label}: rings must be an object")
        return errors
    if bool(rings.get("enabled", False)) and isinstance(rings.get("bands"), list):
        bands = rings.get("bands", [])
        if not bands:
            errors.append(f"{label}: rings.enabled requires at least one band")
        for index, band in enumerate(bands):
            if not isinstance(band, dict):
                continue
            blabel = f"{label} rings.bands[{index}]"
            inner = band.get("inner_radius")
            outer = band.get("outer_radius")
            if not isinstance(inner, (int, float)) or not isinstance(outer, (int, float)) or outer <= inner:
                errors.append(f"{blabel}: inner_radius and outer_radius must be numbers with outer > inner")
            if not _is_hex_colour(band.get("colour")):
                errors.append(f"{blabel}: colour must be #RRGGBB")
        if "outer_radius" in rings:
            outer = rings.get("outer_radius")
            if not isinstance(outer, (int, float)) or outer < 1.0:
                errors.append(f"{label}: rings.outer_radius must be >= 1")
        return errors
    ring_type = str(rings.get("type", "")).strip()
    if ring_type == "none":
        extra = set(rings.keys()) - {"type"}
        if extra:
            errors.append(f"{label}: rings type 'none' must not include {sorted(extra)}")
        return errors
    if ring_type == "small":
        outer_min, outer_max = 1.05, 1.8
    elif ring_type == "broad":
        outer_min, outer_max = 1.8, 2.6
    else:
        errors.append(f"{label}: rings.type must be none, small, or broad")
        return errors
    outer = rings.get("outer_scale")
    if not isinstance(outer, (int, float)) or outer < outer_min or outer > outer_max:
        errors.append(
            f"{label}: rings.outer_scale must be between {outer_min} and {outer_max} for type '{ring_type}'"
        )
    if not _is_hex_colour(rings.get("colour")):
        errors.append(f"{label}: rings.colour must be #RRGGBB")
    return errors


def check_world_sky_backdrop(
    worlds: dict,
    sectors: dict[str, dict],
    stars: dict,
) -> list[str]:
    errors: list[str] = []

    def sector_primary_name(sector_row: dict | None) -> str:
        if not isinstance(sector_row, dict):
            return ""
        return str(sector_row.get("star", "")).strip()

    def sector_system(sector_row: dict | None) -> str:
        if not isinstance(sector_row, dict):
            return ""
        return str(sector_row.get("star_system", "")).strip()

    for world_id, world_data in worlds.items():
        if not isinstance(world_data, dict):
            continue
        sector_row = sectors.get(str(world_id))
        system = sector_system(sector_row)
        primary_name = sector_primary_name(sector_row)

        parent = world_data.get("parent_body")
        if parent is not None:
            label = f"world {world_id} parent_body"
            if not isinstance(parent, dict):
                errors.append(f"{label}: must be an object")
            else:
                name = str(parent.get("name", "")).strip()
                if not name:
                    errors.append(f"{label}: missing name")
                type_id = str(parent.get("type", "")).strip()
                if not type_id:
                    errors.append(f"{label}: missing type")
                errors.extend(check_parent_body_appearance(label, parent.get("appearance")))
                errors.extend(check_parent_body_rings(label, parent.get("rings")))
                angular_min = parent.get("angular_diameter_deg_min")
                angular_max = parent.get("angular_diameter_deg_max")
                if not isinstance(angular_min, (int, float)) or angular_min < 2 or angular_min > 20:
                    errors.append(f"{label}: angular_diameter_deg_min must be between 2 and 20")
                if not isinstance(angular_max, (int, float)) or angular_max < 2 or angular_max > 20:
                    errors.append(f"{label}: angular_diameter_deg_max must be between 2 and 20")
                if (
                    isinstance(angular_min, (int, float))
                    and isinstance(angular_max, (int, float))
                    and angular_min > angular_max
                ):
                    errors.append(f"{label}: angular_diameter_deg_min must not exceed max")

        companions = world_data.get("companion_stars")
        if companions is None:
            continue
        if not isinstance(companions, list):
            errors.append(f"world {world_id} companion_stars: must be an array")
            continue
        for index, entry in enumerate(companions):
            clabel = f"world {world_id} companion_stars[{index}]"
            if not isinstance(entry, dict):
                errors.append(f"{clabel}: must be an object")
                continue
            separation = entry.get("separation_deg")
            if not isinstance(separation, (int, float)):
                errors.append(f"{clabel}: separation_deg must be a number")
            if entry.get("star") is not None:
                star_name = str(entry.get("star", "")).strip()
                if not star_name:
                    errors.append(f"{clabel}: star must be non-empty")
                    continue
                if star_name not in stars:
                    errors.append(f"{clabel}: unknown star '{star_name}'")
                    continue
                star_row = stars[star_name]
                if system and str(star_row.get("star_system", "")) != system:
                    errors.append(
                        f"{clabel}: star '{star_name}' is not in sector system '{system}'"
                    )
                if primary_name and star_name == primary_name:
                    errors.append(
                        f"{clabel}: companion must not duplicate sector primary '{primary_name}'"
                    )
            elif entry.get("name") is not None:
                display = str(entry.get("name", "")).strip()
                if not display:
                    errors.append(f"{clabel}: name must be non-empty")
                for field in ("temperature_k", "luminosity", "disc_radius"):
                    value = entry.get(field)
                    if not isinstance(value, (int, float)) or value <= 0:
                        errors.append(f"{clabel}: {field} must be a number greater than 0")
            else:
                errors.append(f"{clabel}: must include star or name")

    return errors


ENGINE_TYPES = {
    "chemical",
    "hydro_thermal",
    "electric_plasma",
    "direct_fusion",
    "antimatter",
    "gravitic",
    "integrated_sail",
}

PROPULSION_SKU_FLOOR = 40
# Every engine family must keep at least one SKU so a line cannot silently vanish.
PROPULSION_TYPE_FLOORS = {
    "chemical": 1,
    "hydro_thermal": 1,
    "electric_plasma": 1,
    "direct_fusion": 1,
    "antimatter": 1,
    "gravitic": 1,
    "integrated_sail": 1,
}

ENGINE_TYPE_LABELS = {
    "chemical": "Chemical",
    "hydro_thermal": "Hydro-thermal",
    "electric_plasma": "Electric plasma",
    "direct_fusion": "Direct fusion",
    "antimatter": "Antimatter",
    "gravitic": "Gravitic",
    "integrated_sail": "Integrated sail",
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


def check_commodities(commodities: list) -> list[str]:
    errors: list[str] = []
    if not isinstance(commodities, list):
        return ["commodities.json: root must be an array"]
    for entry in commodities:
        if not isinstance(entry, dict):
            continue
        commodity_id = str(entry.get("id", ""))
        caps = entry.get("requires_capabilities", [])
        if caps is None:
            errors.append(f"commodity {commodity_id}: requires_capabilities must be present")
            continue
        if not isinstance(caps, list):
            errors.append(f"commodity {commodity_id}: requires_capabilities must be an array")
            continue
        for cap in caps:
            cap_id = str(cap)
            if cap_id not in CARGO_CAPABILITY_FLAGS:
                errors.append(
                    f"commodity {commodity_id}: invalid requires_capabilities '{cap_id}'"
                )
    return errors


def check_sanctions(doc: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        errors.append("sanctions.json must be an object")
        return errors
    infraction_ids: set[str] = set()
    for entry in doc.get("infractions", []):
        if not isinstance(entry, dict):
            errors.append("sanctions.json: infraction entry must be object")
            continue
        infraction_id = str(entry.get("id", ""))
        if not infraction_id:
            errors.append("sanctions.json: infraction missing id")
            continue
        if infraction_id in infraction_ids:
            errors.append(f"sanctions.json: duplicate infraction id '{infraction_id}'")
        infraction_ids.add(infraction_id)
        fine = entry.get("fine")
        if fine is None:
            errors.append(f"sanctions infraction {infraction_id}: missing fine")
        elif int(fine) < 0:
            errors.append(f"sanctions infraction {infraction_id}: fine must be non-negative")
    return errors


def check_passenger_missions(doc: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        errors.append("passenger_missions.json must be an object")
        return errors

    for key in ("terminal_offers_per_day", "bar_offers_per_day", "base_pay", "friction_pay"):
        if key not in doc:
            errors.append(f"passenger_missions.json: missing {key}")

    fraction = doc.get("cancel_penalty_fraction")
    if fraction is not None and not (0.0 < float(fraction) < 1.0):
        errors.append("passenger_missions.json: cancel_penalty_fraction must be between 0 and 1")

    for key in ("max_hops", "deadline_slack_hours"):
        if key not in doc:
            errors.append(f"passenger_missions.json: missing {key}")
    max_hops = int(doc.get("max_hops", 0) or 0)
    if max_hops < 1:
        errors.append("passenger_missions.json: max_hops must be at least 1")
    slack = doc.get("deadline_slack_hours")
    if slack is not None and float(slack) < 0.0:
        errors.append("passenger_missions.json: deadline_slack_hours must be non-negative")
    orbit = doc.get("deadline_orbit_hours_per_hop")
    if orbit is not None and float(orbit) < 0.0:
        errors.append("passenger_missions.json: deadline_orbit_hours_per_hop must be non-negative")

    allowed_ls = {"spartan", "comfort", "luxury"}
    allowed_aff = {"civilian", "corporate"}
    allowed_boards = {"terminal", "bar"}
    role_ids: set[str] = set()
    for role in doc.get("roles", []):
        if not isinstance(role, dict):
            errors.append("passenger_missions.json: role entry must be object")
            continue
        role_id = str(role.get("id", ""))
        if not role_id:
            errors.append("passenger_missions.json: role missing id")
            continue
        if role_id in role_ids:
            errors.append(f"passenger_missions.json: duplicate role id '{role_id}'")
        role_ids.add(role_id)
        if str(role.get("life_support", "")) not in allowed_ls:
            errors.append(f"passenger_missions role {role_id}: invalid life_support")
        if str(role.get("affiliation", "")) not in allowed_aff:
            errors.append(f"passenger_missions role {role_id}: invalid affiliation")
        if bool(role.get("requires_player_affiliation", False)):
            if str(role.get("affiliation", "")) != "corporate":
                errors.append(
                    f"passenger_missions role {role_id}: affiliation gate requires corporate"
                )
        min_rep = role.get("min_reputation")
        if min_rep is not None and int(min_rep) < 0:
            errors.append(
                f"passenger_missions role {role_id}: min_reputation must be non-negative"
            )
        boards = role.get("boards", ["terminal"])
        if not isinstance(boards, list) or not boards:
            errors.append(f"passenger_missions role {role_id}: boards must be a non-empty array")
        else:
            for board in boards:
                if str(board) not in allowed_boards:
                    errors.append(
                        f"passenger_missions role {role_id}: invalid board '{board}'"
                    )
            if "bar" in [str(b) for b in boards] and str(role.get("affiliation", "")) != "civilian":
                errors.append(
                    f"passenger_missions role {role_id}: bar roles must be civilian"
                )

    for entry in doc.get("descriptions", []):
        if not isinstance(entry, dict):
            errors.append("passenger_missions.json: description entry must be object")
            continue
        if not str(entry.get("id", "")):
            errors.append("passenger_missions.json: description missing id")
        if not str(entry.get("text", "")):
            errors.append("passenger_missions.json: description missing text")
        desc_boards = entry.get("boards", [])
        if not isinstance(desc_boards, list) or not desc_boards:
            errors.append(
                f"passenger_missions description {entry.get('id', '?')}: boards required"
            )
        else:
            for board in desc_boards:
                if str(board) not in allowed_boards:
                    errors.append(
                        f"passenger_missions description {entry.get('id', '?')}: invalid board"
                    )

    return errors


def check_freight_missions(doc: object, commodities: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        errors.append("freight_missions.json must be an object")
        return errors

    for key in ("offers_per_day", "base_pay", "friction_pay", "cancel_penalty_fraction"):
        if key not in doc:
            errors.append(f"freight_missions.json: missing {key}")

    fraction = doc.get("cancel_penalty_fraction")
    if fraction is not None and not (0.0 < float(fraction) < 1.0):
        errors.append("freight_missions.json: cancel_penalty_fraction must be between 0 and 1")

    for key in ("max_hops", "deadline_slack_hours"):
        if key not in doc:
            errors.append(f"freight_missions.json: missing {key}")
    max_hops = int(doc.get("max_hops", 0) or 0)
    if max_hops < 1:
        errors.append("freight_missions.json: max_hops must be at least 1")
    slack = doc.get("deadline_slack_hours")
    if slack is not None and float(slack) < 0.0:
        errors.append("freight_missions.json: deadline_slack_hours must be non-negative")
    orbit = doc.get("deadline_orbit_hours_per_hop")
    if orbit is not None and float(orbit) < 0.0:
        errors.append("freight_missions.json: deadline_orbit_hours_per_hop must be non-negative")

    cargo_ids: set[str] = set()
    for cargo in doc.get("cargos", []):
        if not isinstance(cargo, dict):
            errors.append("freight_missions.json: cargo entry must be object")
            continue
        cargo_id = str(cargo.get("id", ""))
        if not cargo_id:
            errors.append("freight_missions.json: cargo missing id")
            continue
        if cargo_id in cargo_ids:
            errors.append(f"freight_missions.json: duplicate cargo id '{cargo_id}'")
        cargo_ids.add(cargo_id)

        qty_min = int(cargo.get("quantity_min", 0))
        qty_max = int(cargo.get("quantity_max", qty_min))
        if qty_min <= 0 or qty_max < qty_min:
            errors.append(f"freight_missions cargo {cargo_id}: invalid quantity range")

        commodity_id = str(cargo.get("commodity_id", ""))
        if commodity_id:
            if commodity_id not in commodities:
                errors.append(f"freight_missions cargo {cargo_id}: unknown commodity '{commodity_id}'")
            for rate_key in ("life_support_per_unit", "compute_per_unit", "power_per_unit"):
                rate = float(cargo.get(rate_key, 0.0) or 0.0)
                if rate > 0.0:
                    errors.append(
                        f"freight_missions cargo {cargo_id}: {rate_key} must be zero when commodity_id is set"
                    )
        else:
            mass = float(cargo.get("mass_per_unit", 0.0) or 0.0)
            if mass <= 0.0:
                errors.append(f"freight_missions cargo {cargo_id}: mass_per_unit required without commodity_id")

        for rate_key in ("life_support_per_unit", "compute_per_unit", "power_per_unit"):
            rate = cargo.get(rate_key)
            if rate is not None and float(rate) < 0.0:
                errors.append(f"freight_missions cargo {cargo_id}: {rate_key} must be non-negative")

        caps = cargo.get("requires_capabilities", [])
        if caps is not None:
            if not isinstance(caps, list):
                errors.append(f"freight_missions cargo {cargo_id}: requires_capabilities must be array")
            else:
                for cap_id in caps:
                    if str(cap_id) not in CARGO_CAPABILITY_FLAGS:
                        errors.append(
                            f"freight_missions cargo {cargo_id}: invalid capability '{cap_id}'"
                        )

        min_rep = cargo.get("min_reputation")
        if min_rep is not None and int(min_rep) < 0:
            errors.append(
                f"freight_missions cargo {cargo_id}: min_reputation must be non-negative"
            )

    for entry in doc.get("descriptions", []):
        if not isinstance(entry, dict):
            errors.append("freight_missions.json: description entry must be object")
            continue
        if not str(entry.get("id", "")):
            errors.append("freight_missions.json: description missing id")
        if not str(entry.get("text", "")):
            errors.append("freight_missions.json: description missing text")
        allowed = entry.get("cargos", [])
        if not isinstance(allowed, list) or not allowed:
            errors.append(
                f"freight_missions description {entry.get('id', '?')}: cargos required"
            )
        else:
            for ref in allowed:
                ref_id = str(ref)
                if ref_id not in cargo_ids:
                    errors.append(
                        f"freight_missions description {entry.get('id', '?')}: unknown cargo '{ref_id}'"
                    )

    return errors


def check_bounty_missions(doc: object, ships: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        errors.append("bounty_missions.json must be an object")
        return errors

    for key in (
        "peacekeeping_offers_per_day",
        "corporate_bounty_chance",
        "bar_bounty_chance",
        "base_pay",
        "cancel_penalty_fraction",
        "volatile_duration_hours",
        "volatile_return_hours",
    ):
        if key not in doc:
            errors.append(f"bounty_missions.json: missing {key}")

    fraction = doc.get("cancel_penalty_fraction")
    if fraction is not None and not (0.0 < float(fraction) < 1.0):
        errors.append("bounty_missions.json: cancel_penalty_fraction must be between 0 and 1")

    for chance_key in ("corporate_bounty_chance", "bar_bounty_chance"):
        chance = doc.get(chance_key)
        if chance is not None and not (0.0 <= float(chance) <= 1.0):
            errors.append(f"bounty_missions.json: {chance_key} must be between 0 and 1")

    objectives = doc.get("objectives", {})
    if not isinstance(objectives, dict) or not objectives:
        errors.append("bounty_missions.json: objectives must be a non-empty object")
    else:
        for required_id in ("destroy", "intercept", "disable", "eliminate"):
            if required_id not in objectives:
                errors.append(f"bounty_missions.json: missing objective '{required_id}'")
        for obj_id, obj_def in objectives.items():
            if not isinstance(obj_def, dict):
                errors.append(f"bounty_missions objective {obj_id}: must be object")
                continue
            for req in ("title", "verb", "completion", "sources", "difficulty"):
                if req not in obj_def:
                    errors.append(f"bounty_missions objective {obj_id}: missing {req}")
            completion = str(obj_def.get("completion", ""))
            if completion not in ("destroy", "disable"):
                errors.append(
                    f"bounty_missions objective {obj_id}: completion must be destroy or disable"
                )
            sources = obj_def.get("sources", [])
            if not isinstance(sources, list) or not sources:
                errors.append(f"bounty_missions objective {obj_id}: sources required")
            else:
                for src in sources:
                    if str(src) not in VALID_SCAN_SOURCES:
                        errors.append(
                            f"bounty_missions objective {obj_id}: invalid source '{src}'"
                        )
            diff = obj_def.get("difficulty")
            if diff is not None and float(diff) <= 0.0:
                errors.append(f"bounty_missions objective {obj_id}: difficulty must be positive")

    for list_key in ("reasons", "statuses"):
        entries = doc.get(list_key, [])
        if not isinstance(entries, list) or not entries:
            errors.append(f"bounty_missions.json: {list_key} must be a non-empty array")

    threats = doc.get("threats", [])
    if not isinstance(threats, list) or not threats:
        errors.append("bounty_missions.json: threats must be a non-empty array")
    else:
        seen_threats: set[str] = set()
        for threat in threats:
            if not isinstance(threat, dict):
                errors.append("bounty_missions.json: each threat must be an object")
                continue
            threat_id = str(threat.get("id", ""))
            if not threat_id:
                errors.append("bounty_missions.json: threat missing id")
            elif threat_id in seen_threats:
                errors.append(f"bounty_missions.json: duplicate threat '{threat_id}'")
            seen_threats.add(threat_id)
            if not str(threat.get("label", "")).strip():
                errors.append(f"bounty_missions threat {threat_id}: label required")
            mult = threat.get("pay_multiplier")
            if mult is not None and float(mult) <= 0.0:
                errors.append("bounty_missions.json: threat pay_multiplier must be positive")
            profile = threat.get("profile", {})
            if not isinstance(profile, dict):
                errors.append(f"bounty_missions threat {threat_id}: profile must be an object")
            else:
                skill = str(profile.get("pilot_skill", ""))
                if skill not in ("", "novice", "experienced", "elite"):
                    errors.append(
                        f"bounty_missions threat {threat_id}: invalid pilot_skill '{skill}'"
                    )
                escorts = profile.get("escort_count", 0)
                if not isinstance(escorts, int) or escorts < 0:
                    errors.append(
                        f"bounty_missions threat {threat_id}: escort_count must be a non-negative int"
                    )
                hull_scale = profile.get("hull_scale", 1.0)
                if hull_scale is not None and float(hull_scale) <= 0.0:
                    errors.append(
                        f"bounty_missions threat {threat_id}: hull_scale must be positive"
                    )

    sources_cfg = doc.get("sources", {})
    if not isinstance(sources_cfg, dict):
        errors.append("bounty_missions.json: sources must be an object")
    else:
        for src in VALID_SCAN_SOURCES:
            if src not in sources_cfg:
                errors.append(f"bounty_missions.json: missing sources.{src}")
            else:
                src_def = sources_cfg.get(src, {})
                if not isinstance(src_def, dict):
                    continue
                frames = src_def.get("frames", [])
                if not isinstance(frames, list) or not frames:
                    errors.append(f"bounty_missions.json: sources.{src}.frames required")
                else:
                    allowed = {
                        "callsign",
                        "ship",
                        "site",
                        "reason",
                        "status",
                        "threat",
                        "objective",
                        "corp",
                    }
                    for frame in frames:
                        text = str(frame)
                        if not text.strip():
                            errors.append(
                                f"bounty_missions.json: sources.{src} has empty frame"
                            )
                            continue
                        for token in re.findall(r"\{([a-z_]+)\}", text):
                            if token not in allowed:
                                errors.append(
                                    f"bounty_missions.json: sources.{src} unknown placeholder '{{{token}}}'"
                                )

    return errors


def check_corporate_presence(
    sectors: dict[str, dict],
    corporations: dict[str, dict],
    presence: dict[str, object],
    traffic: dict,
) -> list[str]:
    errors: list[str] = []
    sector_ids = set(sectors.keys())
    corp_ids = set(corporations.keys())

    deepspace = corporations.get("deepspace")
    if not isinstance(deepspace, dict):
        errors.append("corporations.json: missing deepspace entry")
    else:
        if str(deepspace.get("name", "")) != "DeepSpace Cooperative":
            errors.append("corporations.json: deepspace name must be 'DeepSpace Cooperative'")
        if str(deepspace.get("callsign_prefix", "")) != "DSC":
            errors.append("corporations.json: deepspace callsign_prefix must be 'DSC'")

    for entry in traffic.get("affiliations", []):
        if not isinstance(entry, dict):
            continue
        if str(entry.get("kind", "")) == "corporate":
            errors.append(
                "traffic.json: corporate affiliations belong in corporations.json"
            )
            break

    if set(presence.keys()) != sector_ids:
        missing = sector_ids - set(presence.keys())
        extra = set(presence.keys()) - sector_ids
        if missing:
            errors.append(
                f"corporate_presence.json: missing sectors {sorted(missing)}"
            )
        if extra:
            errors.append(
                f"corporate_presence.json: unknown sectors {sorted(extra)}"
            )

    for sector_id, block in presence.items():
        if not isinstance(block, dict):
            errors.append(f"corporate_presence.json: sector {sector_id} must be an object")
            continue
        block_ids = set(block.keys())
        if block_ids != corp_ids:
            missing = corp_ids - block_ids
            extra = block_ids - corp_ids
            if missing:
                errors.append(
                    f"corporate_presence {sector_id}: missing corporations {sorted(missing)}"
                )
            if extra:
                errors.append(
                    f"corporate_presence {sector_id}: unknown corporations {sorted(extra)}"
                )
        total = 0.0
        for corp_id, percent in block.items():
            value = float(percent)
            if value <= 0.0:
                errors.append(
                    f"corporate_presence {sector_id}: {corp_id} must be > 0"
                )
            total += value
        if abs(total - 100.0) > 0.011:
            errors.append(
                f"corporate_presence {sector_id}: percents sum to {total:.2f}, expected 100.00"
            )

    return errors


VALID_CORPORATE_AD_VOICES = frozenset(
    {"polished", "blunt", "cheerful", "severe", "slick", "courtly"}
)

VALID_SCAN_SOURCES = frozenset({"peacekeeping", "corporate_office", "bar"})
VALID_SCAN_TARGETS = frozenset(
    {"planet", "volatile_debris", "volatile_orbital", "volatile_ship"}
)
VALID_SCAN_OBJECTIVES = frozenset({"active_scan"})
SCAN_CLIENT_TYPES = frozenset({"inspection", "assessment", "survey"})
SCAN_PEACEKEEPING_TYPES = frozenset({"reconnaissance", "intelligence", "survey"})


def check_scan_missions(doc: object, corporations: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        errors.append("scan_missions.json must be an object")
        return errors

    for key in (
        "peacekeeping_offers_per_day",
        "corporate_offers_per_day",
        "bar_scan_chance",
        "base_pay",
        "cancel_penalty_fraction",
        "volatile_duration_hours",
        "volatile_return_hours",
    ):
        if key not in doc:
            errors.append(f"scan_missions.json: missing {key}")

    types = doc.get("types", {})
    if not isinstance(types, dict) or not types:
        errors.append("scan_missions.json: types must be a non-empty object")
        return errors

    for type_id, type_def in types.items():
        if not isinstance(type_def, dict):
            errors.append(f"scan_missions type {type_id}: must be object")
            continue
        objective = str(type_def.get("objective", ""))
        if objective not in VALID_SCAN_OBJECTIVES:
            errors.append(f"scan_missions type {type_id}: invalid objective '{objective}'")
        sources = type_def.get("sources", [])
        if not isinstance(sources, list) or not sources:
            errors.append(f"scan_missions type {type_id}: sources required")
        else:
            for src in sources:
                if str(src) not in VALID_SCAN_SOURCES:
                    errors.append(f"scan_missions type {type_id}: invalid source '{src}'")
        targets = type_def.get("targets", [])
        if not isinstance(targets, list) or not targets:
            errors.append(f"scan_missions type {type_id}: targets required")
        else:
            for tgt in targets:
                if str(tgt) not in VALID_SCAN_TARGETS:
                    errors.append(f"scan_missions type {type_id}: invalid target '{tgt}'")
        diff = type_def.get("difficulty")
        if diff is not None and float(diff) <= 0.0:
            errors.append(f"scan_missions type {type_id}: difficulty must be positive")

    sources_cfg = doc.get("sources", {})
    if not isinstance(sources_cfg, dict):
        errors.append("scan_missions.json: sources must be an object")
    else:
        for src in VALID_SCAN_SOURCES:
            if src not in sources_cfg:
                errors.append(f"scan_missions.json: missing sources.{src}")
        pk = sources_cfg.get("peacekeeping", {})
        if isinstance(pk, dict):
            frames = pk.get("frames", [])
            if not isinstance(frames, list) or not frames:
                errors.append("scan_missions.json: peacekeeping frames required")
        bar = sources_cfg.get("bar", {})
        if isinstance(bar, dict):
            anon = bar.get("anonymous_frames", [])
            if not isinstance(anon, list) or not anon:
                errors.append("scan_missions.json: bar anonymous_frames required")

    practices = doc.get("practices", {})
    if not isinstance(practices, dict) or not practices:
        errors.append("scan_missions.json: practices must be a non-empty object")
    else:
        if "peacekeeping" not in practices:
            errors.append("scan_missions.json: missing practices.peacekeeping")
        else:
            pk_practice = practices.get("peacekeeping", {})
            if isinstance(pk_practice, dict):
                for req in SCAN_PEACEKEEPING_TYPES:
                    if req not in pk_practice:
                        errors.append(
                            f"scan_missions.json: peacekeeping practice missing '{req}'"
                        )
        for practice_id, practice_def in practices.items():
            if practice_id == "peacekeeping":
                continue
            if not isinstance(practice_def, dict):
                errors.append(f"scan_missions practice {practice_id}: must be object")
                continue
            for req in SCAN_CLIENT_TYPES:
                if req not in practice_def:
                    errors.append(
                        f"scan_missions practice {practice_id}: missing client phrase '{req}'"
                    )

    voices = doc.get("voices", {})
    if not isinstance(voices, dict):
        errors.append("scan_missions.json: voices must be an object")
    else:
        for voice in sorted(VALID_CORPORATE_AD_VOICES):
            if voice not in voices:
                errors.append(f"scan_missions.json: missing voices.{voice}")
                continue
            voice_def = voices.get(voice, {})
            if not isinstance(voice_def, dict):
                continue
            for channel in ("corporate_office", "bar"):
                lines = voice_def.get(channel, [])
                if not isinstance(lines, list) or not lines:
                    errors.append(
                        f"scan_missions.json: voices.{voice}.{channel} must be non-empty"
                    )

    if isinstance(practices, dict):
        valid_practices = set(practices.keys())
        for corp_id, corp in corporations.items():
            if not isinstance(corp, dict):
                continue
            practice = str(corp.get("practice", "")).strip()
            if not practice:
                errors.append(f"corporations.json: {corp_id} missing practice")
            elif practice not in valid_practices:
                errors.append(
                    f"corporations.json: {corp_id} practice '{practice}' unknown in scan_missions"
                )

    return errors


def check_volatile_sites(doc: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        errors.append("volatile_sites.json must be an object")
        return errors
    sites = doc.get("sites", [])
    if not isinstance(sites, list) or not sites:
        errors.append("volatile_sites.json: sites must be a non-empty array")
        return errors
    seen_ids: set[str] = set()
    for index, entry in enumerate(sites):
        if not isinstance(entry, dict):
            errors.append(f"volatile_sites.json: sites[{index}] must be an object")
            continue
        site_id = str(entry.get("id", "")).strip()
        if not site_id:
            errors.append(f"volatile_sites.json: sites[{index}] missing id")
            continue
        if site_id in seen_ids:
            errors.append(f"volatile_sites.json: duplicate site id '{site_id}'")
        seen_ids.add(site_id)
        label = str(entry.get("label", "")).strip()
        if not label:
            errors.append(f"volatile_sites.json: {site_id} missing label")
        if "star" not in entry:
            errors.append(f"volatile_sites.json: {site_id} missing star flag")
        elif not isinstance(entry.get("star"), bool):
            errors.append(f"volatile_sites.json: {site_id} star must be boolean")
        article = str(entry.get("article", "")).strip()
        if article not in ("a", "an", "the"):
            errors.append(f"volatile_sites.json: {site_id} article must be a, an, or the")
        if "objects" not in entry:
            continue
        objects = entry.get("objects")
        if not isinstance(objects, list):
            errors.append(f"volatile_sites.json: {site_id} objects must be an array")
            continue
        seen_kinds: set[str] = set()
        for object_index, spec in enumerate(objects):
            if not isinstance(spec, dict):
                errors.append(
                    f"volatile_sites.json: {site_id} objects[{object_index}] must be an object"
                )
                continue
            kind = str(spec.get("kind", "")).strip()
            if kind == "npc_ship":
                kind = "ship"
            allowed_kinds = (
                "debris",
                "orbital",
                "derelict",
                "cargo",
                "marker",
                "mine",
                "ship",
            )
            if kind not in allowed_kinds:
                errors.append(
                    f"volatile_sites.json: {site_id} objects[{object_index}] "
                    f"kind must be one of {', '.join(allowed_kinds)}"
                )
                continue
            if kind in seen_kinds:
                errors.append(f"volatile_sites.json: {site_id} duplicate object kind '{kind}'")
            seen_kinds.add(kind)
            count = spec.get("count")
            if (
                not isinstance(count, list)
                or len(count) != 2
                or not all(isinstance(value, int) and not isinstance(value, bool) for value in count)
            ):
                errors.append(
                    f"volatile_sites.json: {site_id} {kind} count must be [min, max] integers"
                )
                continue
            lo, hi = int(count[0]), int(count[1])
            if lo < 0 or hi < lo or hi > 32:
                errors.append(
                    f"volatile_sites.json: {site_id} {kind} count must satisfy 0 <= min <= max <= 32"
                )
    return errors


def check_corporation_office_ticker(
    corporations: dict[str, dict],
    ships: dict[str, dict],
    modules: list[dict],
    ticker_config: dict,
) -> list[str]:
    errors: list[str] = []
    voices = ticker_config.get("voices", {})
    if not isinstance(voices, dict):
        errors.append("corporate_office_ticker.json: voices must be an object")
        return errors
    for voice in sorted(VALID_CORPORATE_AD_VOICES):
        if voice not in voices:
            errors.append(f"corporate_office_ticker.json: missing voice '{voice}'")

    sku_labels: set[str] = set()
    for ship in ships.values():
        if not isinstance(ship, dict):
            continue
        name = str(ship.get("name", "")).strip()
        if name:
            sku_labels.add(name)
        brand = str(ship.get("brand", "")).strip()
        if brand:
            sku_labels.add(brand)
    for module in modules:
        if not isinstance(module, dict):
            continue
        name = str(module.get("name", "")).strip()
        if name:
            sku_labels.add(name)
        brand = str(module.get("brand", "")).strip()
        if brand:
            sku_labels.add(brand)

    for corp_id, corp in sorted(corporations.items()):
        if not isinstance(corp, dict):
            continue
        voice = str(corp.get("ad_voice", "")).strip()
        if voice not in VALID_CORPORATE_AD_VOICES:
            errors.append(
                f"corporations.json: {corp_id} ad_voice '{voice}' is not a known office voice"
            )
        brands = corp.get("brands", [])
        if not isinstance(brands, list) or not brands:
            errors.append(f"corporations.json: {corp_id} brands must be a non-empty array")
            continue
        for brand_variant in brands:
            label = str(brand_variant).strip()
            if not label:
                errors.append(f"corporations.json: {corp_id} brands must not contain empty strings")
                continue
            if label in sku_labels:
                errors.append(
                    f"corporations.json: {corp_id} brand '{label}' duplicates a catalogue SKU name or brand"
                )

    return errors


def catalog_art_to_path(art: str) -> Path | None:
    if not art.startswith("res://"):
        return None
    return ROOT / art.removeprefix("res://")


MODULE_ICON_CATEGORIES = [
    "propulsion",
    "power",
    "computer",
    "life_support",
    "sensor",
    "navigation",
    "hyperdrive",
    "weapon",
    "armour",
    "cargo",
    "fuel",
    "ammunition",
    "shield",
    "point_defence",
    "cyber_defence",
    "transponder",
]


def check_module_category_icons() -> list[str]:
    errors: list[str] = []
    for category in MODULE_ICON_CATEGORIES:
        path = ROOT / "assets" / "ui" / "modules" / f"{category}.png"
        if not path.is_file():
            errors.append(
                f"module icon: missing assets/ui/modules/{category}.png"
            )
    return errors


def check_chassis_ui_headers(chassis: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    for chassis_id, entry in sorted(chassis.items()):
        header = str(entry.get("header", ""))
        if not header:
            errors.append(f"chassis {chassis_id}: missing header")
            continue
        sprite = str(entry.get("sprite", ""))
        if header == sprite:
            errors.append(
                f"chassis {chassis_id}: header must differ from world sprite"
            )
        if not header.startswith("res://assets/ui/ships/"):
            errors.append(
                f"chassis {chassis_id}: header must be under res://assets/ui/ships/"
            )
            continue
        path = catalog_art_to_path(header)
        if path is None or not path.is_file():
            rel = header.removeprefix("res://")
            errors.append(f"chassis {chassis_id}: header file not found '{rel}'")
    return errors


def check_habitat_building_uniqueness(
    habitats: dict[str, dict],
    buildings: dict[str, dict],
) -> list[str]:
    errors: list[str] = []
    building_owner: dict[str, str] = {}
    art_owner: dict[str, str] = {}

    def register_art(art: str, label: str) -> None:
        if not art:
            errors.append(f"{label}: missing art path")
            return
        prior = art_owner.get(art)
        if prior and prior != label:
            errors.append(f"{label}: art '{art}' already used by {prior}")
        else:
            art_owner[art] = label
        path = catalog_art_to_path(art)
        if path is None:
            errors.append(f"{label}: art must be under res://assets/ui/locations/")
            return
        if not path.is_file():
            errors.append(f"{label}: art file not found '{path.relative_to(ROOT)}'")

    for habitat_id, habitat in sorted(habitats.items()):
        register_art(str(habitat.get("art", "")), f"habitat {habitat_id}")

        building_ids = habitat.get("buildings", [])
        if not isinstance(building_ids, list):
            errors.append(f"habitat {habitat_id}: buildings must be an array")
            continue

        shipyard_count = 0
        for building_id_variant in building_ids:
            building_id = str(building_id_variant)
            if not building_id:
                continue
            prior_habitat = building_owner.get(building_id)
            if prior_habitat:
                errors.append(
                    f"building {building_id}: listed on habitats "
                    f"'{prior_habitat}' and '{habitat_id}'"
                )
            else:
                building_owner[building_id] = habitat_id

            building = buildings.get(building_id)
            if not building:
                continue
            register_art(str(building.get("art", "")), f"building {building_id}")
            if str(building.get("type", "")) == "shipyard":
                shipyard_count += 1

        if shipyard_count > 1:
            errors.append(
                f"habitat {habitat_id}: expected at most one shipyard building, "
                f"found {shipyard_count}"
            )

    return errors


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


MESSAGE_CHANNELS = {"headlines", "gossip"}

MESSAGE_TONES = {"info", "warning", "positive", "negative"}

PLOT_TRIGGER_KINDS = {"event", "days_in_state", "gig_accepted", "gig_completed"}

PLOT_GIG_DESKS = {"terminal", "bar", "peacekeeping", "corporate", "any"}

SIM_EVENT_TYPES = {
    "sector_entered",
    "docked",
    "undocked",
    "commodity_traded",
    "ship_purchased",
    "module_installed",
    "credits_changed",
    "ship_destroyed",
    "salvage_taken",
}

MESSAGE_PLACEHOLDERS = {
    "habitat",
    "planet",
    "planet2",
    "celebrity",
    "corporation",
    "rival",
    "corporation-ticker",
    "rival-ticker",
    "brand",
    "rival-brand",
    "sport",
    "shift",
    "city-mall",
    "city-mall2",
    "celebrity-pilot",
    "local-star-system-location",
    "jump-destination",
    "commodity",
    "price",
    "move",
    "destination",
    "quantity",
    "label",
    "desk",
    "product",
    "title",
}

MESSAGE_INTEGER_RANGE_RE = re.compile(r"^\d+-\d+$")

STAR_FIELDS = {
    "star_system",
    "spectral_class",
    "temperature_k",
    "luminosity",
    "mass_solar",
    "radius_solar",
    "description",
}

STAR_POSITIVE_NUMBERS = {"temperature_k", "luminosity", "mass_solar", "radius_solar"}

PLACEHOLDER_RE = re.compile(r"\{([^{}]+)\}")


def message_template_token_allowed(token: str) -> bool:
    if token in MESSAGE_PLACEHOLDERS:
        return True
    if MESSAGE_INTEGER_RANGE_RE.match(token):
        return True
    if "|" in token:
        parts = [part.strip() for part in token.split("|")]
        return bool(parts) and all(parts)
    return False


def check_fuels(fuels: list, modules: list) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for index, fuel in enumerate(fuels):
        label = f"fuels.json[{index}]"
        if not isinstance(fuel, dict):
            errors.append(f"{label}: entry must be an object")
            continue
        fuel_id = str(fuel.get("id", "")).strip()
        if not fuel_id:
            errors.append(f"{label}: missing id")
            continue
        label = f"fuels.json {fuel_id}"
        if fuel_id in seen:
            errors.append(f"{label}: duplicate id")
        seen.add(fuel_id)
        price_min = fuel.get("price_min")
        price_max = fuel.get("price_max")
        if isinstance(price_min, bool) or not isinstance(price_min, (int, float)):
            errors.append(f"{label}: price_min must be a number")
            continue
        if isinstance(price_max, bool) or not isinstance(price_max, (int, float)):
            errors.append(f"{label}: price_max must be a number")
            continue
        if price_min < 0 or price_max < price_min:
            errors.append(f"{label}: price_max must be at least price_min, both non-negative")
    for module in modules:
        if not isinstance(module, dict):
            continue
        fuel_type = str(module.get("fuel_type", "")).strip()
        if not fuel_type:
            continue
        module_id = str(module.get("id", "?"))
        if fuel_type not in seen:
            errors.append(f"modules {module_id}: unknown fuel_type '{fuel_type}'")
    return errors


def check_message_emitters(emitters: list) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for index, emitter in enumerate(emitters):
        label = f"message_emitters.json[{index}]"
        if not isinstance(emitter, dict):
            errors.append(f"{label}: entry must be an object")
            continue
        emitter_id = str(emitter.get("id", "")).strip()
        if not emitter_id:
            errors.append(f"{label}: missing id")
            continue
        label = f"message_emitters.json {emitter_id}"
        if emitter_id in seen:
            errors.append(f"{label}: duplicate id")
        seen.add(emitter_id)
        weight = emitter.get("weight")
        if isinstance(weight, bool) or not isinstance(weight, (int, float)) or weight <= 0:
            errors.append(f"{label}: weight must be a number greater than 0")
        templates = emitter.get("templates")
        if not isinstance(templates, list) or not templates:
            errors.append(f"{label}: templates must be a non-empty array")
            continue
        for template_index, template in enumerate(templates):
            template_label = f"{label} templates[{template_index}]"
            if not isinstance(template, dict):
                errors.append(f"{template_label}: template must be an object")
                continue
            channel = str(template.get("channel", ""))
            if channel not in MESSAGE_CHANNELS:
                errors.append(f"{template_label}: unknown channel '{channel}'")
            text = template.get("text")
            if not isinstance(text, str) or not text.strip():
                errors.append(f"{template_label}: text must be a non-empty string")
                text = ""
            tone = str(template.get("tone", ""))
            if tone not in MESSAGE_TONES:
                errors.append(f"{template_label}: unknown tone '{tone}'")
            for token in PLACEHOLDER_RE.findall(text):
                if not message_template_token_allowed(token):
                    errors.append(f"{template_label}: unknown placeholder '{{{token}}}'")
    return errors


def check_plotlines(plotlines: list) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for index, plotline in enumerate(plotlines):
        label = f"plotlines.json[{index}]"
        if not isinstance(plotline, dict):
            errors.append(f"{label}: entry must be an object")
            continue
        plotline_id = str(plotline.get("id", "")).strip()
        if not plotline_id:
            errors.append(f"{label}: missing id")
            continue
        label = f"plotlines.json {plotline_id}"
        if plotline_id in seen:
            errors.append(f"{label}: duplicate id")
        seen.add(plotline_id)
        initial = str(plotline.get("initial", "")).strip()
        states = plotline.get("states")
        if not isinstance(states, dict) or not states:
            errors.append(f"{label}: states must be a non-empty object")
            continue
        if not initial:
            errors.append(f"{label}: missing initial")
        elif initial not in states:
            errors.append(f"{label}: initial '{initial}' is not a state id")
        for state_id, state in states.items():
            state_label = f"{label} states.{state_id}"
            if not isinstance(state, dict):
                errors.append(f"{state_label}: state must be an object")
                continue
            messages = state.get("messages", [])
            if messages is not None and not isinstance(messages, list):
                errors.append(f"{state_label}: messages must be an array")
            elif isinstance(messages, list):
                for msg_index, msg in enumerate(messages):
                    msg_label = f"{state_label} messages[{msg_index}]"
                    if not isinstance(msg, dict):
                        errors.append(f"{msg_label}: message must be an object")
                        continue
                    channel = str(msg.get("channel", ""))
                    if channel not in MESSAGE_CHANNELS:
                        errors.append(f"{msg_label}: unknown channel '{channel}'")
                    text = msg.get("text")
                    if not isinstance(text, str) or not text.strip():
                        errors.append(f"{msg_label}: text must be a non-empty string")
                        text = ""
                    for token in PLACEHOLDER_RE.findall(text):
                        if not message_template_token_allowed(token):
                            errors.append(f"{msg_label}: unknown placeholder '{{{token}}}'")
                    weight = msg.get("weight", 1.0)
                    if isinstance(weight, bool) or not isinstance(weight, (int, float)) or weight <= 0:
                        errors.append(f"{msg_label}: weight must be a number greater than 0")
            gigs = state.get("gigs", [])
            if gigs is not None and not isinstance(gigs, list):
                errors.append(f"{state_label}: gigs must be an array")
            elif isinstance(gigs, list):
                gig_ids: set[str] = set()
                for gig_index, gig in enumerate(gigs):
                    gig_label = f"{state_label} gigs[{gig_index}]"
                    if not isinstance(gig, dict):
                        errors.append(f"{gig_label}: gig must be an object")
                        continue
                    gig_id = str(gig.get("id", "")).strip()
                    if not gig_id:
                        errors.append(f"{gig_label}: missing id")
                    elif gig_id in gig_ids:
                        errors.append(f"{gig_label}: duplicate gig id '{gig_id}'")
                    else:
                        gig_ids.add(gig_id)
                    desk = str(gig.get("desk", ""))
                    if desk not in PLOT_GIG_DESKS:
                        errors.append(f"{gig_label}: unknown desk '{desk}'")
                    title = gig.get("title")
                    if not isinstance(title, str) or not title.strip():
                        errors.append(f"{gig_label}: title must be a non-empty string")
                    text = gig.get("text")
                    if not isinstance(text, str) or not text.strip():
                        errors.append(f"{gig_label}: text must be a non-empty string")
                    habitats = gig.get("habitats")
                    if habitats is not None and not isinstance(habitats, list):
                        errors.append(f"{gig_label}: habitats must be an array when present")
            transitions = state.get("transitions", [])
            if transitions is not None and not isinstance(transitions, list):
                errors.append(f"{state_label}: transitions must be an array")
            elif isinstance(transitions, list):
                for tr_index, transition in enumerate(transitions):
                    tr_label = f"{state_label} transitions[{tr_index}]"
                    if not isinstance(transition, dict):
                        errors.append(f"{tr_label}: transition must be an object")
                        continue
                    to_state = str(transition.get("to", "")).strip()
                    if not to_state:
                        errors.append(f"{tr_label}: missing to")
                    elif to_state not in states:
                        errors.append(f"{tr_label}: to '{to_state}' is not a state id")
                    when = transition.get("when")
                    if not isinstance(when, dict):
                        errors.append(f"{tr_label}: when must be an object")
                        continue
                    kind = str(when.get("kind", ""))
                    if kind not in PLOT_TRIGGER_KINDS:
                        errors.append(f"{tr_label}: unknown when.kind '{kind}'")
                        continue
                    if kind == "event":
                        event_type = str(when.get("type", ""))
                        if event_type not in SIM_EVENT_TYPES:
                            errors.append(f"{tr_label}: unknown event type '{event_type}'")
                    elif kind == "days_in_state":
                        days = when.get("days")
                        if isinstance(days, bool) or not isinstance(days, (int, float)) or days < 0:
                            errors.append(f"{tr_label}: days must be a non-negative number")
                    elif kind in ("gig_accepted", "gig_completed"):
                        gig_id = str(when.get("gig_id", "")).strip()
                        if not gig_id:
                            errors.append(f"{tr_label}: gig_id required for {kind}")
                    require_flags = transition.get("require_flags")
                    if require_flags is not None and not isinstance(require_flags, dict):
                        errors.append(f"{tr_label}: require_flags must be an object")
                    set_flags = transition.get("set_flags")
                    if set_flags is not None and not isinstance(set_flags, dict):
                        errors.append(f"{tr_label}: set_flags must be an object")
                    require_plotline = transition.get("require_plotline")
                    if require_plotline is not None:
                        if not isinstance(require_plotline, dict):
                            errors.append(f"{tr_label}: require_plotline must be an object")
                        else:
                            other_id = str(require_plotline.get("id", "")).strip()
                            other_state = str(require_plotline.get("state", "")).strip()
                            if not other_id:
                                errors.append(f"{tr_label}: require_plotline.id required")
                            if not other_state:
                                errors.append(f"{tr_label}: require_plotline.state required")
    return errors


def check_celebrity_pilots(pilots: list) -> list[str]:
    errors: list[str] = []
    seen_ids: set[str] = set()
    seen_names: set[str] = set()
    for index, pilot in enumerate(pilots):
        label = f"celebrity_pilots.json[{index}]"
        if not isinstance(pilot, dict):
            errors.append(f"{label}: entry must be an object")
            continue
        pilot_id = str(pilot.get("id", "")).strip()
        name = str(pilot.get("name", "")).strip()
        if not pilot_id:
            errors.append(f"{label}: missing id")
            continue
        label = f"celebrity_pilots.json {pilot_id}"
        if pilot_id in seen_ids:
            errors.append(f"{label}: duplicate id")
        seen_ids.add(pilot_id)
        if not name:
            errors.append(f"{label}: missing name")
            continue
        if name in seen_names:
            errors.append(f"{label}: duplicate name '{name}'")
        seen_names.add(name)
    return errors


def check_stars(stars: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(stars, dict) or not stars:
        return ["stars.json: must be a non-empty object keyed by star name"]
    for name, row in stars.items():
        star_name = str(name).strip()
        label = f"stars.json {star_name or '?'}"
        if not star_name:
            errors.append("stars.json: empty star name")
            continue
        if not isinstance(row, dict):
            errors.append(f"{label}: entry must be an object")
            continue
        extra = sorted(set(row.keys()) - STAR_FIELDS)
        if extra:
            errors.append(f"{label}: unknown fields {extra}")
        for field in sorted(STAR_FIELDS - set(row.keys())):
            errors.append(f"{label}: missing {field}")
        star_system = row.get("star_system")
        spectral_class = row.get("spectral_class")
        description = row.get("description")
        if not isinstance(star_system, str) or not star_system.strip():
            errors.append(f"{label}: star_system must be a non-empty string")
        if not isinstance(spectral_class, str) or not spectral_class.strip():
            errors.append(f"{label}: spectral_class must be a non-empty string")
        if not isinstance(description, str) or not description.strip():
            errors.append(f"{label}: description must be a non-empty string")
        for field in sorted(STAR_POSITIVE_NUMBERS):
            value = row.get(field)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                errors.append(f"{label}: {field} must be a number greater than 0")
    return errors



def check_module_rule_makers(corporations: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    names = {str(row.get("name", "")) for row in corporations.values() if isinstance(row, dict)}
    for category, makers in sorted(MODULE_RULES.get("makers", {}).items()):
        if not isinstance(makers, list):
            errors.append(f"module_rules.json makers.{category} must be an array")
            continue
        for maker in makers:
            if str(maker) not in names:
                errors.append(
                    f"module_rules.json makers.{category}: '{maker}' is not a corporation name"
                )
    return errors


def main() -> int:
    sectors = index_by_id(load_array(CATALOG / "sectors.json"))
    habitats = index_by_id(load_array(CATALOG / "habitats.json"))
    buildings_by_id = index_by_id(load_array(CATALOG / "buildings.json"))
    chassis = index_by_id(load_array(CATALOG / "chassis.json"))
    ships = index_by_id(load_array(CATALOG / "ships.json"))
    interactables = index_by_id(load_array(CATALOG / "interactables.json"))
    routes = load_array(CATALOG / "routes.json")
    unspaces = load_array(CATALOG / "unspaces.json")
    worlds = load_object(CATALOG / "worlds.json")
    player = load_object(CATALOG / "player.json")
    backgrounds_doc = load_object(CATALOG / "backgrounds.json")
    corporations = index_by_id(load_array(CATALOG / "corporations.json"))
    corporate_presence = load_object(CATALOG / "corporate_presence.json")
    traffic = load_object(CATALOG / "traffic.json")
    passenger_missions = load_object(CATALOG / "passenger_missions.json")
    freight_missions = load_object(CATALOG / "freight_missions.json")
    bounty_missions = load_object(CATALOG / "bounty_missions.json")
    scan_missions = load_object(CATALOG / "scan_missions.json")
    volatile_sites = load_object(CATALOG / "volatile_sites.json")
    sanctions_doc = load_object(CATALOG / "sanctions.json")
    commodities = load_array(CATALOG / "commodities.json")
    commodities_by_id = index_by_id(commodities)

    errors: list[str] = []
    errors.extend(check_module_rule_makers(corporations))

    errors.extend(check_sanctions(sanctions_doc))
    errors.extend(check_commodities(commodities))
    errors.extend(check_fuels(load_array(CATALOG / "fuels.json"), load_modules()))
    errors.extend(check_message_emitters(load_array(CATALOG / "message_emitters.json")))
    errors.extend(check_plotlines(load_array(CATALOG / "plotlines.json")))
    errors.extend(check_celebrity_pilots(load_array(CATALOG / "celebrity_pilots.json")))
    errors.extend(check_stars(load_object(CATALOG / "stars.json")))
    errors.extend(check_passenger_missions(passenger_missions))
    errors.extend(check_freight_missions(freight_missions, commodities_by_id))
    errors.extend(check_bounty_missions(bounty_missions, ships))
    errors.extend(check_scan_missions(scan_missions, corporations))
    errors.extend(check_volatile_sites(volatile_sites))
    errors.extend(
        check_corporate_presence(sectors, corporations, corporate_presence, traffic)
    )
    errors.extend(
        check_corporation_office_ticker(
            corporations,
            ships,
            load_modules(),
            load_object(CATALOG / "corporate_office_ticker.json"),
        )
    )

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

        rep = background.get("reputation")
        if rep is not None and int(rep) < 0:
            errors.append(f"background {background_id}: reputation must be non-negative")

        kit_sanctions = background.get("sanctions", [])
        if kit_sanctions is not None:
            if not isinstance(kit_sanctions, list):
                errors.append(f"background {background_id}: sanctions must be an array")
            else:
                infraction_ids = {
                    str(entry.get("id", ""))
                    for entry in sanctions_doc.get("infractions", [])
                    if isinstance(entry, dict)
                }
                for infraction_id in kit_sanctions:
                    if str(infraction_id) not in infraction_ids:
                        errors.append(
                            f"background {background_id}: unknown sanction '{infraction_id}'"
                        )

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

    cargo_count = 0
    for module in modules:
        if not isinstance(module, dict):
            continue
        module_id = str(module.get("id", ""))
        if str(module.get("category", "")) != "cargo":
            continue
        cargo_count += 1
        for field in ("maker", "brand", "cargo_capacity"):
            if field not in module:
                errors.append(f"cargo module {module_id}: missing {field}")
        maker = str(module.get("maker", ""))
        if maker and maker not in CARGO_MAKERS:
            errors.append(f"cargo module {module_id}: unknown maker '{maker}'")
        capabilities = module.get("capabilities", [])
        if capabilities is None:
            errors.append(f"cargo module {module_id}: capabilities must be present (use [])")
            continue
        if not isinstance(capabilities, list):
            errors.append(f"cargo module {module_id}: capabilities must be an array")
            continue
        for cap in capabilities:
            cap_id = str(cap)
            if cap_id not in CARGO_CAPABILITY_FLAGS:
                errors.append(f"cargo module {module_id}: invalid capability '{cap_id}'")
        capacity = float(module.get("cargo_capacity", 0.0))
        if capacity <= 0.0:
            errors.append(f"cargo module {module_id}: cargo_capacity must be > 0")
    if cargo_count < CARGO_SKU_FLOOR:
        errors.append(
            f"modules.json: expected at least {CARGO_SKU_FLOOR} cargo SKUs, found {cargo_count}"
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
        if maker in BANNED_PROPULSION_MAKERS:
            errors.append(f"propulsion module {module_id}: {maker} must not make engines")
        engine_type = str(module.get("engine_type", ""))
        if engine_type and engine_type not in ENGINE_TYPES:
            errors.append(f"propulsion module {module_id}: invalid engine_type '{engine_type}'")
        if engine_type in propulsion_type_counts:
            propulsion_type_counts[engine_type] += 1
        if str(module.get("mount", "")) != "main_engine":
            errors.append(f"propulsion module {module_id}: mount must be 'main_engine'")
        if engine_type == "integrated_sail" and float(module.get("fuel_consumption", -1.0)) != 0.0:
            errors.append(
                f"propulsion module {module_id}: integrated_sail fuel_consumption must be 0"
            )
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
            if maker in BANNED_WEAPON_MAKERS:
                errors.append(f"weapon module {module_id}: {maker} must not make weapons")
            if maker and maker not in WEAPON_MAKERS:
                errors.append(f"weapon module {module_id}: unknown maker '{maker}'")
            if module_id in RETIRED_WEAPON_IDS:
                errors.append(f"modules.json: retired weapon id '{module_id}' still present")
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
            if maker in BANNED_ARMOUR_MAKERS:
                errors.append(f"armour module {module_id}: {maker} must not make armour")
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
        elif category == "hyperdrive":
            for field in ("maker", "brand", "power_demand", "compute_demand"):
                if field not in module:
                    errors.append(f"hyperdrive module {module_id}: missing {field}")
            maker = str(module.get("maker", ""))
            if maker and maker not in HYPERDRIVE_MAKERS:
                errors.append(f"hyperdrive module {module_id}: unknown maker '{maker}'")
            if str(module.get("mount", "")) != "system":
                errors.append(f"hyperdrive module {module_id}: mount must be 'system'")

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
                if (
                    str(module.get("core_type", "")) == "quantum"
                    and str(chassis_id) != "blackbird_chassis"
                ):
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

    solutions_by_source: dict[str, set[int]] = {}
    for route in routes:
        route_id = str(route.get("id", "?"))
        for end in ("a", "b"):
            sector_id = str(route.get(end, ""))
            if sector_id and sector_id not in sectors:
                errors.append(f"route {route_id}: unknown sector '{sector_id}'")
        translations = route.get("translations")
        if not isinstance(translations, list) or not translations:
            errors.append(f"route {route_id}: missing translations array")
            continue
        has_n4 = False
        a = str(route.get("a", ""))
        b = str(route.get("b", ""))
        for entry in translations:
            if not isinstance(entry, dict):
                errors.append(f"route {route_id}: translation entry must be object")
                continue
            n = int(entry.get("n", 0))
            if n <= 0:
                errors.append(f"route {route_id}: invalid translation n={n}")
            if n == 4:
                has_n4 = True
            if "solution_ab" not in entry or "solution_ba" not in entry:
                errors.append(f"route {route_id}: translation missing solution_ab/solution_ba")
                continue
            if a:
                ab = int(entry["solution_ab"])
                solutions_by_source.setdefault(a, set())
                if ab in solutions_by_source[a]:
                    errors.append(f"route {route_id}: duplicate solution {ab} for source '{a}'")
                solutions_by_source[a].add(ab)
            if b:
                ba = int(entry["solution_ba"])
                solutions_by_source.setdefault(b, set())
                if ba in solutions_by_source[b]:
                    errors.append(f"route {route_id}: duplicate solution {ba} for source '{b}'")
                solutions_by_source[b].add(ba)
        if not has_n4:
            errors.append(f"route {route_id}: translations must include n=4 public entry")

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

    errors.extend(check_module_category_icons())
    errors.extend(check_chassis_ui_headers(chassis))
    errors.extend(check_habitat_building_uniqueness(habitats, buildings_by_id))
    errors.extend(check_sector_completeness(CATALOG))
    errors.extend(check_unspace_completeness(unspaces))
    errors.extend(check_world_entity_kinds(worlds))
    errors.extend(
        check_world_sky_backdrop(
            worlds,
            sectors,
            load_object(CATALOG / "stars.json"),
        )
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
