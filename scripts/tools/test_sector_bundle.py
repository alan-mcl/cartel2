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

from generate_sector_bundle import apply_bundle, build_bundle, validate_spec
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

        bundle = build_bundle(spec)
        apply_bundle(self.catalog_dir, bundle, replace=False)

        errors = check(self.catalog_dir)
        self.assertEqual(errors, [], msg="\n".join(errors))


if __name__ == "__main__":
    unittest.main()
