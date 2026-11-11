#!/usr/bin/env python3
"""Assign surface_population_billions and habitat population_billions per B13 rules."""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[2] / "data" / "catalog"
SECTORS_PATH = CATALOG / "sectors.json"
HABITATS_PATH = CATALOG / "habitats.json"

SURFACE_FIXED: dict[str, float] = {
    "new_ceres": 0.02,
    "junkers_world": 0.02,
    "byrsa": 0.05,
    "acb2": 0.02,
    "aurelia": 0.02,
    "scoria": 0.02,
    "caldera": 0.02,
    "denarius_ii": 0.01,
    "typhon_xvi": 0.01,
    "ursa_xvi": 0.01,
    "titania_ixx": 0.01,
    "nightjar": 0.01,
    "janus": 0.01,
    "titania_v": 0.0,
}

SURFACE_CAMP: dict[str, str] = {
    "new_ceres": "Ceres Aerie",
    "junkers_world": "Emerald Camp",
    "byrsa": "Byrsa Stack",
    "acb2": "Scar Pit",
    "aurelia": "Aurelia Camp",
    "scoria": "Scoria Camp",
    "caldera": "Caldera Camp",
    "denarius_ii": "Denarius Camp",
    "typhon_xvi": "Typhon Camp",
    "ursa_xvi": "Ursa Camp",
    "titania_ixx": "Titania Camp",
    "nightjar": "Nightjar Camp",
    "janus": "Janus Camp",
}


def to_milli(value: float) -> int:
    return round(value * 1000.0)


def from_milli(milli: int) -> float:
    return round(milli / 1000.0, 3)


def surface_milli_for_sector(sector: dict) -> int:
    sid = str(sector["id"])
    total_milli = to_milli(float(sector.get("population_billions", 0.0)))
    if sid in SURFACE_FIXED:
        return to_milli(SURFACE_FIXED[sid])
    classification = str(sector.get("classification", "")).strip()
    if classification:
        return total_milli * 96 // 100
    return 0


def orbital_shares_milli(orbital_milli: int, habitats: list[dict], stations: list[dict]) -> list[tuple[str, int]]:
    ordered: list[tuple[str, str]] = []
    for row in sorted(habitats, key=lambda x: str(x["id"])):
        ordered.append(("habitat", str(row["id"])))
    for row in sorted(stations, key=lambda x: str(x["id"])):
        ordered.append(("station", str(row["id"])))
    if not ordered:
        return []

    if not stations:
        return [(ordered[0][1], orbital_milli)]

    intent_weights: list[tuple[str, int]] = []
    if not stations:
        intent_weights = [(ordered[0][1], orbital_milli)]
    else:
        habitat_milli = orbital_milli * 75 // 100
        station_pool = orbital_milli - habitat_milli
        per_station = station_pool // len(stations)
        habitat_id = ordered[0][1]
        intent_weights.append((habitat_id, habitat_milli))
        for _kind, station_id in ordered[1:]:
            intent_weights.append((station_id, per_station))

    # Last orbital absorbs rounding.
    out: list[tuple[str, int]] = []
    assigned = 0
    for habitat_id, share in intent_weights[:-1]:
        milli = max(0, share)
        out.append((habitat_id, milli))
        assigned += milli
    last_id = intent_weights[-1][0]
    out.append((last_id, max(0, orbital_milli - assigned)))
    return out


def main() -> None:
    sectors: list[dict] = json.loads(SECTORS_PATH.read_text(encoding="utf-8"))
    habitats: list[dict] = json.loads(HABITATS_PATH.read_text(encoding="utf-8"))
    by_sector: dict[str, list[dict]] = defaultdict(list)
    for row in habitats:
        by_sector[str(row["sector_id"])].append(row)

    for sector in sectors:
        sid = str(sector["id"])
        total_milli = to_milli(float(sector.get("population_billions", 0.0)))
        surface_milli = surface_milli_for_sector(sector)
        if surface_milli > total_milli:
            raise SystemExit(f"{sid}: surface {surface_milli} exceeds total {total_milli}")
        orbital_milli = total_milli - surface_milli
        sector["surface_population_billions"] = from_milli(surface_milli)

        rows = by_sector.get(sid, [])
        habitats_rows = [r for r in rows if str(r.get("type", "")) == "habitat"]
        station_rows = [r for r in rows if str(r.get("type", "")) == "station"]
        shares = orbital_shares_milli(orbital_milli, habitats_rows, station_rows)
        if orbital_milli > 0 and not shares:
            raise SystemExit(f"{sid}: orbital population but no habitats")
        share_ids = {hid for hid, _ in shares}
        for hid, milli in shares:
            for row in rows:
                if str(row["id"]) == hid:
                    row["population_billions"] = from_milli(milli)
                    break
        for row in rows:
            hid = str(row["id"])
            if hid not in share_ids:
                row["population_billions"] = 0.0

        classification = str(sector.get("classification", "")).strip()
        if not classification and surface_milli > 0:
            camp = SURFACE_CAMP.get(sid)
            if not camp:
                raise SystemExit(f"{sid}: surface population but no camp name")
            sector["city_malls"] = [camp]

    # Verify sums.
    for sector in sectors:
        sid = str(sector["id"])
        total = float(sector["population_billions"])
        surface = float(sector.get("surface_population_billions", 0.0))
        orbital = sum(
            float(h.get("population_billions", 0.0)) for h in by_sector.get(sid, [])
        )
        if abs(total - (surface + orbital)) > 0.0005:
            raise SystemExit(
                f"{sid}: split mismatch total={total} surface={surface} orbital={orbital}"
            )

    SECTORS_PATH.write_text(
        json.dumps(sectors, indent="\t", ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    HABITATS_PATH.write_text(
        json.dumps(habitats, indent="\t", ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    catalog_total = sum(float(s["population_billions"]) for s in sectors)
    print(f"Assigned population split for {len(sectors)} sectors (total {catalog_total:.2f} bn).")


if __name__ == "__main__":
    main()
