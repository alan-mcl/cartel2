#!/usr/bin/env python3
"""Assign non-habitat orbital sprites from processed PNG art."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPRITE_PREFIX = "res://assets/world/orbitals/"

HQ_LABEL_ORDER = [
    "Creus Corporation Headquarters",
    "SnedeCorp Headquarters",
    "Morrow & Sons Headquarters",
    "Mercury Communications Headquarters",
    "Galactic Outcomes Headquarters",
    "General Industrial Headquarters",
    "Orion Aerospace Headquarters",
    "GRC Inc Headquarters",
    "The Octagon Headquarters",
    "Crown & Anchor Headquarters",
    "Fellowship of Apex Headquarters",
    "Chimera Corporation Headquarters",
    "Terra Nova Headquarters",
]


def list_textures(assets_dir: Path) -> list[str]:
    return sorted(p.name for p in assets_dir.glob("*.png") if p.is_file())


def headquarters_texture_pool(assets_dir: Path) -> list[str]:
    names = list_textures(assets_dir)

    def ch_rank(name: str, tier: int) -> tuple[int, str]:
        return tier, name

    pool: list[str] = []
    for tier, pattern in (
        (0, re.compile(r"^corporate_headquarters_\d+_l\.png$")),
        (1, re.compile(r"^corporate_campus_\d+_l\.png$")),
        (2, re.compile(r"^corporate_headquarters_\d+_m\.png$")),
    ):
        matches = sorted(n for n in names if pattern.match(n))
        pool.extend(matches)
    return pool[: len(HQ_LABEL_ORDER)]


def collect_orbitals(worlds: dict) -> tuple[list[dict], list[dict]]:
    labelled: list[dict] = []
    unlabelled: list[dict] = []
    label_index = {label: i for i, label in enumerate(HQ_LABEL_ORDER)}

    for sector_id in sorted(worlds.keys()):
        ring = worlds[sector_id].get("orbital_ring") or {}
        for orbital in ring.get("orbitals") or []:
            if orbital.get("kind") != "orbital":
                continue
            row = {
                "sector_id": sector_id,
                "id": orbital.get("id", ""),
                "label": str(orbital.get("label", "")).strip(),
                "sprite_before": orbital.get("sprite", ""),
            }
            if row["label"]:
                row["sort_key"] = label_index.get(row["label"], 999)
                labelled.append(row)
            else:
                unlabelled.append(row)

    labelled.sort(key=lambda r: r["sort_key"])
    return labelled, unlabelled


def assign(
    assets_dir: Path,
    labelled: list[dict],
    unlabelled: list[dict],
) -> tuple[list[dict], Counter[str]]:
    hq_pool = headquarters_texture_pool(assets_dir)
    if len(hq_pool) < len(labelled):
        raise RuntimeError(f"need {len(labelled)} HQ textures, pool has {len(hq_pool)}")

    assignments: list[dict] = []
    used_hq = set(hq_pool[: len(labelled)])

    for row, texture in zip(labelled, hq_pool[: len(labelled)], strict=True):
        assignments.append(
            {
                **row,
                "sprite_file": texture,
                "sprite": f"{SPRITE_PREFIX}{texture}",
                "role": "headquarters",
            }
        )

    remainder = [n for n in list_textures(assets_dir) if n not in used_hq]
    if not remainder:
        raise RuntimeError("no textures left for unlabelled orbitals")

    by_sector: dict[str, list[dict]] = defaultdict(list)
    for row in unlabelled:
        by_sector[row["sector_id"]].append(row)

    pool_index = 0
    for sector_id in sorted(by_sector.keys()):
        for row in by_sector[sector_id]:
            texture = remainder[pool_index % len(remainder)]
            pool_index += 1
            assignments.append(
                {
                    **row,
                    "sprite_file": texture,
                    "sprite": f"{SPRITE_PREFIX}{texture}",
                    "role": "ambient",
                }
            )

    usage = Counter(a["sprite_file"] for a in assignments)
    return assignments, usage


def apply(worlds_path: Path, assignments: list[dict]) -> int:
    worlds = json.loads(worlds_path.read_text(encoding="utf-8"))
    by_id: dict[tuple[str, str], dict] = {
        (a["sector_id"], a["id"]): a for a in assignments
    }
    touched = 0
    for sector_id, data in worlds.items():
        ring = data.get("orbital_ring") or {}
        for orbital in ring.get("orbitals") or []:
            if orbital.get("kind") != "orbital":
                continue
            key = (sector_id, orbital.get("id", ""))
            match = by_id.get(key)
            if match is None:
                continue
            orbital["sprite"] = match["sprite"]
            if "modulate" in orbital:
                del orbital["modulate"]
            touched += 1
    worlds_path.write_text(json.dumps(worlds, indent="\t") + "\n", encoding="utf-8")
    return touched


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--assets",
        type=Path,
        default=ROOT / "assets/world/orbitals",
        help="directory of cutout PNG filenames",
    )
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    worlds = json.loads((ROOT / "data/catalog/worlds.json").read_text(encoding="utf-8"))
    labelled, unlabelled = collect_orbitals(worlds)
    assignments, usage = assign(args.assets, labelled, unlabelled)

    if len(labelled) != len(HQ_LABEL_ORDER):
        print(f"WARNING: expected {len(HQ_LABEL_ORDER)} HQ labels, found {len(labelled)}")

    if args.json_out:
        args.json_out.write_text(json.dumps(assignments, indent=2), encoding="utf-8")

    for row in assignments:
        label = row["label"] or "(unlabelled)"
        print(f"{row['role']:12}  {row['sector_id']:16}  {label[:42]:42}  {row['sprite_file']}")

    print("\nTextures used more than once:")
    for name, count in sorted(usage.items()):
        if count > 1:
            print(f"  {name}: {count}")

    if args.apply:
        n = apply(ROOT / "data/catalog/worlds.json", assignments)
        print(f"\nApplied {n} orbital sprite paths.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
