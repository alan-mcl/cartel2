#!/usr/bin/env bash
# Godot import + GDScript parse sweep (+ optional gdlint).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"
SCRIPT_DIRS=(scripts/gameplay scripts/presentation scripts/ui scripts/dev tests)

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
	exit 1
fi

# shellcheck source=scripts/ci/lib.sh
source "$ROOT/scripts/ci/lib.sh"

echo "== GDScript parse sweep =="
ci_run_godot_script "GDScript parse sweep" "res://scripts/ci/check_scripts.gd"

if [[ "${CARTEL_GDLINT:-}" == "1" ]] && command -v gdlint >/dev/null 2>&1; then
	echo "== gdlint (advisory, CARTEL_GDLINT=1) =="
	gdlint "${SCRIPT_DIRS[@]}" || echo "gdlint reported issues (not failing the check)." >&2
elif [[ "${CARTEL_GDLINT:-}" == "1" ]]; then
	echo "== gdlint skipped (not installed: pip install gdtoolkit) ==" >&2
else
	echo "== gdlint skipped (set CARTEL_GDLINT=1 to run) =="
fi
