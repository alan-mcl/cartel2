#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
	exit 1
fi

# shellcheck source=scripts/ci/lib.sh
source "$ROOT/scripts/ci/lib.sh"

ci_run_godot_script "Scene smoke suite" "res://scripts/dev/smoke_scenes.gd" "SMOKE FAIL"
