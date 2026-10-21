#!/usr/bin/env bash
# Run a Godot scene from the repo root (interactive window).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"

if [[ $# -lt 1 ]]; then
	echo "Usage: $(basename "$0") res://scenes/dev/<scene>.tscn [extra godot args...]" >&2
	exit 1
fi

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
	exit 1
fi

exec "$GODOT" --path "$ROOT" --scene "$1" "${@:2}"
