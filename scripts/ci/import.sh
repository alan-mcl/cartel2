#!/usr/bin/env bash
# Reimport Godot assets (project cache).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
	exit 1
fi

echo "== Godot import =="
"$GODOT" --headless --path "$ROOT" --import --quit
