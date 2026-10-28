#!/usr/bin/env bash
#
# Cartel verification script.
#
#   ./scripts/ci/check.sh                 full check (default) - run before marking work done
#   ./scripts/ci/check.sh --fast          validators + unit tests, no import or script sweep
#   ./scripts/ci/check.sh --scripts-only  import + GDScript parse sweep
#   ./scripts/ci/check.sh --tests-only    unit tests only (no smokes)
#
# Godot exits 0 even when a script has parse errors, so every Godot step greps its output for
# error markers instead of trusting the exit code. Do not "simplify" that away, and never pair
# --check-only with --debug (the interactive debugger can hang).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"
ERROR_PATTERN='SCRIPT ERROR|Parse Error|Failed to load script'
SCRIPT_DIRS=(scripts/gameplay scripts/presentation scripts/ui scripts/dev tests)

RUN_VALIDATORS=1
RUN_IMPORT=1
RUN_SWEEP=1
RUN_TESTS=1
RUN_SMOKES=1

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
	--fast)
		RUN_IMPORT=0
		RUN_SWEEP=0
		RUN_SMOKES=0
      ;;
    --scripts-only)
      RUN_VALIDATORS=0
      RUN_TESTS=0
      ;;
    --tests-only)
      RUN_VALIDATORS=0
      RUN_IMPORT=0
      RUN_SWEEP=0
      RUN_SMOKES=0
      ;;
    --jobs)
      echo "NOTE: --jobs is retired; the parse sweep runs in one Godot process." >&2
      shift
      if [[ $# -gt 0 ]]; then
        shift
      fi
      continue
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! -x "$GODOT" ]]; then
  echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
  exit 1
fi

if [[ $RUN_VALIDATORS -eq 1 ]]; then
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
fi

if [[ $RUN_IMPORT -eq 1 ]]; then
  echo "== Godot import =="
  "$GODOT" --headless --path "$ROOT" --import --quit
fi

if [[ $RUN_SWEEP -eq 1 ]]; then
  echo "== GDScript parse sweep =="
  set +e
  SWEEP_OUTPUT=$("$GODOT" --headless --path "$ROOT" --script res://scripts/ci/check_scripts.gd 2>&1)
  SWEEP_EXIT=$?
  set -e
  echo "$SWEEP_OUTPUT"
  if echo "$SWEEP_OUTPUT" | grep -qE "$ERROR_PATTERN"; then
    echo "GDScript parse sweep failed." >&2
    exit 1
  fi
  if [[ $SWEEP_EXIT -ne 0 ]]; then
    echo "GDScript parse sweep exited $SWEEP_EXIT." >&2
    exit 1
  fi

  if command -v gdlint >/dev/null 2>&1; then
    echo "== gdlint (advisory) =="
    gdlint "${SCRIPT_DIRS[@]}" || echo "gdlint reported issues (not failing the check)." >&2
  else
    echo "== gdlint skipped (not installed: pip install gdtoolkit) =="
  fi
fi

if [[ $RUN_TESTS -eq 1 ]]; then
  echo "== Unit tests =="
  set +e
  TEST_OUTPUT=$("$GODOT" --headless --path "$ROOT" --script res://tests/run.gd 2>&1)
  TEST_EXIT=$?
  set -e
  echo "$TEST_OUTPUT"

  if echo "$TEST_OUTPUT" | grep -qE "$ERROR_PATTERN"; then
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
fi

if [[ $RUN_SMOKES -eq 1 ]]; then
	echo "== Scene smoke suite =="
	bash "$ROOT/scripts/ci/smoke_scenes.sh"
fi

echo "All checks passed."
