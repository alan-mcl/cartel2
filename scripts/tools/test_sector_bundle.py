#!/usr/bin/env python3
"""Tests for sector bundle generator and completeness validator."""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]
EXAMPLE_SPEC = TOOLS / "sector_spec.example.json"

import sys

if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import index_by_id, load_array, load_object
from generate_sector_bundle import (
    apply_bundle,
    build_bundle,
    corporate_building_id,
    corporate_office_count,
    top_corporation_ids,
    validate_spec,
)
from validate_catalog_refs import check_corporate_presence
from validate_sector_completeness import check


class SectorBundleTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.catalog_dir = Path(self._tmpdir.name) / "catalog"
        shutil.copytree(ROOT / "data" / "catalog", self.catalog_dir)

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def test_live_catalog_is_complete(self) -> None:
        errors = check(ROOT / "data" / "catalog")
        self.assertEqual(errors, [])

    def test_missing_world_fails_completeness(self) -> None:
        worlds_path = self.catalog_dir / "worlds.json"
        worlds = __import__("json").loads(worlds_path.read_text(encoding="utf-8"))
        worlds.pop("tycho", None)
        worlds_path.write_text(
            __import__("json").dumps(worlds, indent=2) + "\n",
            encoding="utf-8",
        )
        errors = check(self.catalog_dir)
        self.assertTrue(any("tycho" in err and "world" in err for err in errors))

    def test_generate_example_passes_completeness(self) -> None:
        import json

        spec = json.loads(EXAMPLE_SPEC.read_text(encoding="utf-8"))
        errors = validate_spec(spec, self.catalog_dir, replace=False)
        self.assertEqual(errors, [], msg="\n".join(errors))

        corporations = load_array(self.catalog_dir / "corporations.json")
        bundle = build_bundle(spec, corporations)
        apply_bundle(self.catalog_dir, bundle, replace=False)

        errors = check(self.catalog_dir)
        self.assertEqual(errors, [], msg="\n".join(errors))
        errors = check_corporate_presence(
            index_by_id(load_array(self.catalog_dir / "sectors.json")),
            index_by_id(corporations),
            load_object(self.catalog_dir / "corporate_presence.json"),
            load_object(self.catalog_dir / "traffic.json"),
        )
        self.assertEqual(errors, [], msg="\n".join(errors))

        habitats = index_by_id(load_array(self.catalog_dir / "habitats.json"))
        buildings = habitats["example_sector_habitat"]["buildings"]
        self.assertIn("example_sector_peaceforce", buildings)
        office_ids = [
            corporate_building_id(corp_id, "example_sector")
            for corp_id in top_corporation_ids(
                bundle["presence"], corporate_office_count("example_sector")
            )
        ]
        self.assertEqual(corporate_office_count("example_sector"), 2)
        for office_id in office_ids:
            self.assertIn(office_id, buildings)

    def test_live_liaison_offices_follow_presence(self) -> None:
        catalog = ROOT / "data" / "catalog"
        presence = load_object(catalog / "corporate_presence.json")
        habitats = load_array(catalog / "habitats.json")
        buildings = index_by_id(load_array(catalog / "buildings.json"))
        checked = 0
        for habitat in habitats:
            if not isinstance(habitat, dict):
                continue
            if str(habitat.get("type", "habitat")) == "station":
                continue
            sector_id = str(habitat.get("sector_id", ""))
            peace_id = f"{sector_id}_peaceforce"
            listed = [str(item) for item in habitat.get("buildings", [])]
            if peace_id not in listed:
                continue
            row = presence[sector_id]
            for corp_id in top_corporation_ids(row, corporate_office_count(sector_id)):
                office_id = corporate_building_id(corp_id, sector_id)
                has_liaison = office_id in listed
                has_hq = any(
                    str(buildings.get(building_id, {}).get("corporation_id", "")) == corp_id
                    and buildings.get(building_id, {}).get("headquarters") is True
                    for building_id in listed
                )
                self.assertTrue(
                    has_liaison or has_hq,
                    msg=f"{sector_id} missing a desk for {corp_id}",
                )
            checked += 1
        self.assertGreaterEqual(checked, 11)

    def test_bundle_without_peacekeeping_skips_desks(self) -> None:
        import json

        spec = json.loads(EXAMPLE_SPEC.read_text(encoding="utf-8"))
        spec.pop("peacekeeping")
        corporations = load_array(self.catalog_dir / "corporations.json")
        bundle = build_bundle(spec, corporations)
        building_ids = [building["id"] for building in bundle["buildings"]]
        self.assertNotIn("example_sector_peaceforce", building_ids)
        self.assertTrue(bundle["presence"])


if __name__ == "__main__":
    unittest.main()
