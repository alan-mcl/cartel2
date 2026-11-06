#!/usr/bin/env bash
# Python catalog and sheet validators (no Godot).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "== Ship template validation =="
python3 scripts/tools/validate_ship_templates.py

echo "== Catalog record generation =="
python3 scripts/tools/generate_catalog_records.py --check

echo "== Catalog schema validation =="
python3 scripts/tools/validate_catalog_schema.py

echo "== Catalog referential checks =="
python3 scripts/tools/validate_catalog_refs.py

echo "== Sector bundle tests =="
python3 scripts/tools/test_sector_bundle.py

echo "== Catalog sheet tests =="
python3 scripts/tools/test_catalog_sheet.py
