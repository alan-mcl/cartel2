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
        errors = validate_spec(spec, self.catalog_dir)
        self.assertEqual(errors, [], msg="\n".join(errors))

        corporations = load_array(self.catalog_dir / "corporations.json")
        bundle = build_bundle(spec, corporations)
        apply_bundle(self.catalog_dir, bundle)

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


SENTINEL = "HAND_EDIT_SENTINEL_KEEP"


class CatalogWriterGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.catalog_dir = Path(self._tmpdir.name) / "catalog"
        shutil.copytree(ROOT / "data" / "catalog", self.catalog_dir)

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def _inject_sentinels(self) -> None:
        import json

        buildings = load_array(self.catalog_dir / "buildings.json")
        buildings[0]["description"] = SENTINEL
        (self.catalog_dir / "buildings.json").write_text(
            json.dumps(buildings, indent="\t") + "\n",
            encoding="utf-8",
        )

        sectors = load_array(self.catalog_dir / "sectors.json")
        sectors[0]["description"] = SENTINEL
        (self.catalog_dir / "sectors.json").write_text(
            json.dumps(sectors, indent=2) + "\n",
            encoding="utf-8",
        )

        routes = load_array(self.catalog_dir / "routes.json")
        routes[0]["friction"] = 999
        (self.catalog_dir / "routes.json").write_text(
            json.dumps(routes, indent=2) + "\n",
            encoding="utf-8",
        )

        traffic = load_object(self.catalog_dir / "traffic.json")
        traffic["visual_contact_radius"] = 999.0
        (self.catalog_dir / "traffic.json").write_text(
            json.dumps(traffic, indent=2) + "\n",
            encoding="utf-8",
        )

        presence = load_object(self.catalog_dir / "corporate_presence.json")
        first_sector = next(iter(presence))
        presence[first_sector]["creus"] = 42.42
        (self.catalog_dir / "corporate_presence.json").write_text(
            json.dumps(presence, indent="\t") + "\n",
            encoding="utf-8",
        )

    def _assert_sentinels(self) -> None:
        buildings = load_array(self.catalog_dir / "buildings.json")
        self.assertEqual(buildings[0].get("description"), SENTINEL)

        sectors = load_array(self.catalog_dir / "sectors.json")
        self.assertEqual(sectors[0].get("description"), SENTINEL)

        routes = load_array(self.catalog_dir / "routes.json")
        self.assertEqual(routes[0].get("friction"), 999)

        traffic = load_object(self.catalog_dir / "traffic.json")
        self.assertEqual(traffic.get("visual_contact_radius"), 999.0)

        presence = load_object(self.catalog_dir / "corporate_presence.json")
        first_sector = next(iter(presence))
        self.assertEqual(presence[first_sector].get("creus"), 42.42)

    def test_sync_corporate_hqs_preserves_hand_edits(self) -> None:
        import sync_corporate_hqs as sync_hqs

        self._inject_sentinels()
        before = (self.catalog_dir / "buildings.json").read_bytes()
        original_catalog = sync_hqs.CATALOG
        try:
            sync_hqs.CATALOG = self.catalog_dir
            sync_hqs.main()
        finally:
            sync_hqs.CATALOG = original_catalog
        self._assert_sentinels()
        after = (self.catalog_dir / "buildings.json").read_bytes()
        self.assertEqual(before, after)

    def test_generate_corporate_presence_preserves_hand_edits(self) -> None:
        import generate_corporate_presence as gen_presence

        self._inject_sentinels()
        original_catalog = gen_presence.CATALOG
        try:
            gen_presence.CATALOG = self.catalog_dir
            gen_presence.main()
        finally:
            gen_presence.CATALOG = original_catalog
        self._assert_sentinels()

    def test_patch_module_signatures_preserves_hand_edits(self) -> None:
        import patch_module_signatures as patch_sigs

        self._inject_sentinels()
        original_modules = patch_sigs.MODULES_DIR
        original_traffic = patch_sigs.TRAFFIC_PATH
        try:
            patch_sigs.MODULES_DIR = self.catalog_dir / "modules"
            patch_sigs.TRAFFIC_PATH = self.catalog_dir / "traffic.json"
            patch_sigs.main()
        finally:
            patch_sigs.MODULES_DIR = original_modules
            patch_sigs.TRAFFIC_PATH = original_traffic
        self._assert_sentinels()

    def test_sector_bundle_reapply_preserves_hand_edits(self) -> None:
        import json

        from generate_sector_bundle import apply_bundle, build_bundle, validate_spec

        spec = json.loads(EXAMPLE_SPEC.read_text(encoding="utf-8"))
        corporations = load_array(self.catalog_dir / "corporations.json")
        bundle = build_bundle(spec, corporations)
        apply_bundle(self.catalog_dir, bundle)
        self._inject_sentinels()
        errors = validate_spec(spec, self.catalog_dir)
        self.assertTrue(errors)
        self._assert_sentinels()

    def test_rewrite_combat_catalog_does_not_write(self) -> None:
        import rewrite_combat_catalog as rewrite

        weapon_path = self.catalog_dir / "modules" / "weapon.json"
        before = weapon_path.read_text(encoding="utf-8")
        exit_code = rewrite.main()
        self.assertEqual(exit_code, 1)
        self.assertEqual(weapon_path.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
