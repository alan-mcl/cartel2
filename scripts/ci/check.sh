#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"
if [[ ! -x "$GODOT" ]]; then
  echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
  exit 1
fi

echo "== Ship template validation =="
python3 scripts/tools/validate_ship_templates.py

echo "== Catalog referential checks =="
python3 scripts/tools/validate_catalog_refs.py

echo "== Godot import =="
"$GODOT" --headless --path "$ROOT" --import --quit

echo "== GDScript check-only =="
SCRIPT_ERRORS=0
while IFS= read -r -d '' script; do
  rel="${script#"$ROOT"/}"
  res_path="res://${rel}"
  output=$("$GODOT" --headless --path "$ROOT" --check-only --script "$res_path" 2>&1) || true
  if echo "$output" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script'; then
    echo "ERROR: $rel" >&2
    echo "$output" >&2
    SCRIPT_ERRORS=$((SCRIPT_ERRORS + 1))
  fi
done < <(find scripts/gameplay scripts/presentation scripts/ui scripts/dev -name '*.gd' -print0 | sort -z)

if [[ $SCRIPT_ERRORS -gt 0 ]]; then
  echo "== $SCRIPT_ERRORS script(s) failed check-only ==" >&2
  exit 1
fi

echo "== Unit tests =="
set +e
TEST_OUTPUT=$("$GODOT" --headless --path "$ROOT" --script res://tests/run.gd 2>&1)
TEST_EXIT=$?
set -e
echo "$TEST_OUTPUT"

if echo "$TEST_OUTPUT" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script'; then
  echo "Unit test runner hit script errors." >&2
  exit 1
fi
if echo "$TEST_OUTPUT" | grep -q 'FAIL:'; then
  echo "Unit tests failed." >&2
  exit 1
fi
if [[ $TEST_EXIT -ne 0 ]]; then
  echo "Unit test runner exited $TEST_EXIT." >&2
  exit 1
fi

echo "All checks passed."
