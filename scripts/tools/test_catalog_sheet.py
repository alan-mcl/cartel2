#!/usr/bin/env python3
"""Tests for catalog CSV export/import."""

from __future__ import annotations

import csv
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]

if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import CATALOG
from catalog_sheet import (
    Target,
    export_target,
    import_target,
    record_from_row,
    read_csv_rows,
    collect_column_hints,
    load_records_for_target,
    resolve_target,
)


class CatalogSheetTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.catalog_dir = Path(self._tmpdir.name) / "catalog"
        shutil.copytree(CATALOG, self.catalog_dir)

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def _target(self, target_id: str) -> Target:
        t = resolve_target(target_id, self.catalog_dir)
        if t.path.parent.name == "modules":
            path = self.catalog_dir / "modules" / t.path.name
        else:
            path = self.catalog_dir / t.path.name
        return Target(t.target_id, path, t.kind, t.array_key)

    def _round_trip(self, target_id: str) -> None:
        t = self._target(target_id)
        before = t.path.read_bytes()
        csv_path = Path(self._tmpdir.name) / f"{target_id.replace('/', '_')}.csv"
        export_target(t, csv_path)
        changed = import_target(t, csv_path, drop_missing=False, catalog=self.catalog_dir)
        after = t.path.read_bytes()
        self.assertFalse(changed, msg=target_id)
        self.assertEqual(before, after, msg=target_id)

    def test_noop_round_trip_byte_identical(self) -> None:
        for target_id in (
            "passenger.descriptions",
            "freight.descriptions",
            "commodities",
            "routes",
            "modules/propulsion",
        ):
            with self.subTest(target_id=target_id):
                self._round_trip(target_id)

    def test_one_cell_edit_routes(self) -> None:
        t = self._target("routes")
        csv_path = Path(self._tmpdir.name) / "routes.csv"
        export_target(t, csv_path)
        with csv_path.open(encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        for row in rows:
            if row["id"] == "proxima_irasia":
                row["friction"] = "16"
        with csv_path.open("w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
        before_lines = t.path.read_text(encoding="utf-8").splitlines()
        self.assertTrue(import_target(t, csv_path, drop_missing=False, catalog=self.catalog_dir))
        after_lines = t.path.read_text(encoding="utf-8").splitlines()
        changed = [i for i, (a, b) in enumerate(zip(before_lines, after_lines)) if a != b]
        self.assertEqual(changed, [1])
        self.assertIn('"friction": 16', after_lines[1])

    def test_blank_vs_empty_array(self) -> None:
        t = self._target("passenger.descriptions")
        records = load_records_for_target(t, self.catalog_dir)
        hints = collect_column_hints(records)
        sample = next(r for r in records if r.get("roles") == [])
        row = {k: "" for k in ["id", "boards", "text", "roles"]}
        row["id"] = sample["id"]
        row["boards"] = "terminal"
        row["text"] = sample["text"]
        row["roles"] = "[]"
        rebuilt = record_from_row(sample, row, list(row.keys()), hints)
        self.assertEqual(rebuilt["roles"], [])

    def test_dotted_signature_column(self) -> None:
        t = self._target("modules/propulsion")
        records = load_records_for_target(t, self.catalog_dir)
        hints = collect_column_hints(records)
        sample = records[0]
        csv_path = Path(self._tmpdir.name) / "prop.csv"
        export_target(t, csv_path)
        cols, rows = read_csv_rows(csv_path)
        row = next(r for r in rows if r["id"] == sample["id"])
        row["signature.thermal"] = "9.99"
        rebuilt = record_from_row(sample, row, cols, hints)
        self.assertAlmostEqual(rebuilt["signature"]["thermal"], 9.99)

    def test_duplicate_id_rejected(self) -> None:
        t = self._target("commodities")
        csv_path = Path(self._tmpdir.name) / "dup.csv"
        export_target(t, csv_path)
        text = csv_path.read_text(encoding="utf-8")
        first = text.splitlines()[1]
        csv_path.write_text(text.splitlines()[0] + "\n" + first + "\n" + first + "\n", encoding="utf-8")
        with self.assertRaises(SystemExit):
            import_target(t, csv_path, drop_missing=False, catalog=self.catalog_dir)

    def test_drop_missing(self) -> None:
        t = self._target("commodities")
        csv_path = Path(self._tmpdir.name) / "subset.csv"
        export_target(t, csv_path)
        with csv_path.open(encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        keep = rows[0]
        with csv_path.open("w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=keep.keys())
            writer.writeheader()
            writer.writerow(keep)
        self.assertTrue(import_target(t, csv_path, drop_missing=True, catalog=self.catalog_dir))
        data = __import__("json").loads(t.path.read_text(encoding="utf-8"))
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["id"], keep["id"])


if __name__ == "__main__":
    unittest.main()
