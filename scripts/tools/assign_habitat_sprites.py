#!/usr/bin/env python3
"""Print habitat -> sprite assignments and optionally patch worlds.json."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SIZE_SLOTS = ("xl", "l", "m", "s")
SIZE_COUNTS = {"xl": 7, "l": 19, "m": 28, "s": 11}
SPRITE_PREFIX = "res://assets/world/habitats/"


def habitat_record(habitats_by_id: dict, interactable: str) -> dict | None:
    if interactable in habitats_by_id:
        return habitats_by_id[interactable]
    if interactable == "bela_habitat":
        return habitats_by_id.get("bela_orbital_habitat")
    return None


def collect_sorted_habitats(worlds: dict, habitats: list[dict]) -> list[dict]:
    by_id = {h["id"]: h for h in habitats}
    rows: list[dict] = []
    for sector_id, data in worlds.items():
        ring = data.get("orbital_ring") or {}
        for orbital in ring.get("orbitals") or []:
            if orbital.get("kind") != "habitat":
                continue
            interactable = str(orbital.get("interactable", ""))
            if interactable == "proxima_habitat":
                continue
            record = habitat_record(by_id, interactable)
            pop = float(record.get("population_billions", 0)) if record else 0.0
            rows.append(
                {
                    "sector_id": sector_id,
                    "interactable": interactable,
                    "label": orbital.get("label", ""),
                    "orbital_id": orbital.get("id", ""),
                    "population_billions": pop,
                }
            )
    rows.sort(key=lambda r: r["population_billions"], reverse=True)
    return rows


def texture_paths(processed_root: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for size in SIZE_SLOTS:
        folder = processed_root / size
        names = sorted(p.name for p in folder.glob("*.png") if p.is_file())
        out[size] = names
    return out


def build_assignments(rows: list[dict], textures: dict[str, list[str]]) -> tuple[list[dict], list[str]]:
    assignments: list[dict] = []
    unused: list[str] = []
    idx = 0
    for size in SIZE_SLOTS:
        pool = list(textures.get(size, []))
        take = SIZE_COUNTS[size]
        chunk = rows[idx : idx + take]
        idx += take
        for row, filename in zip(chunk, pool, strict=False):
            assignments.append(
                {
                    **row,
                    "size_class": size,
                    "sprite_file": filename,
                    "sprite": f"{SPRITE_PREFIX}{filename}",
                }
            )
        if len(pool) > len(chunk):
            unused.extend(pool[len(chunk) :])
    return assignments, unused


def apply(worlds_path: Path, assignments: list[dict]) -> int:
    worlds = json.loads(worlds_path.read_text(encoding="utf-8"))
    by_interactable = {a["interactable"]: a for a in assignments}
    changed = 0
    for data in worlds.values():
        ring = data.get("orbital_ring") or {}
        for orbital in ring.get("orbitals") or []:
            if orbital.get("kind") != "habitat":
                continue
            interactable = str(orbital.get("interactable", ""))
            if interactable == "proxima_habitat":
                continue
            assignment = by_interactable.get(interactable)
            if assignment is None:
                continue
            orbital["sprite"] = assignment["sprite"]
            if "modulate" in orbital:
                del orbital["modulate"]
                changed += 1
            elif orbital.get("sprite") != assignment["sprite"]:
                changed += 1
            else:
                changed += 1
    worlds_path.write_text(json.dumps(worlds, indent="\t") + "\n", encoding="utf-8")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--processed",
        type=Path,
        default=ROOT / "temp/habitats/processed",
        help="bgremove output root with s/m/l/xl subfolders",
    )
    parser.add_argument("--apply", action="store_true", help="write worlds.json sprite paths")
    parser.add_argument("--json-out", type=Path, help="write assignment table JSON")
    args = parser.parse_args()

    habitats = json.loads((ROOT / "data/catalog/habitats.json").read_text(encoding="utf-8"))
    worlds = json.loads((ROOT / "data/catalog/worlds.json").read_text(encoding="utf-8"))
    rows = collect_sorted_habitats(worlds, habitats)
    textures = texture_paths(args.processed)
    assignments, unused = build_assignments(rows, textures)

    if len(assignments) != len(rows):
        print(f"WARNING: assigned {len(assignments)} habitats but found {len(rows)} orbitals")

    if args.json_out:
        args.json_out.write_text(json.dumps(assignments, indent=2), encoding="utf-8")

    for row in assignments:
        print(
            f"{row['population_billions']:7.3f}  {row['size_class']:2}  {row['label']:40}  {row['sprite_file']}"
        )
    if unused:
        print("\nUnused textures:")
        for name in unused:
            print(f"  {name}")

    if args.apply:
        n = apply(ROOT / "data/catalog/worlds.json", assignments)
        print(f"\nApplied {len(assignments)} sprite paths to worlds.json ({n} orbital records touched).")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
