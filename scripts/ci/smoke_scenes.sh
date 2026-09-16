#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"
ERROR_PATTERN='SCRIPT ERROR|Parse Error|Failed to load script|^ERROR:|SMOKE FAIL'

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
	exit 1
fi

set +e
OUTPUT=$("$GODOT" --headless --path "$ROOT" --script res://scripts/dev/smoke_scenes.gd 2>&1)
STATUS=$?
set -e
printf '%s\n' "$OUTPUT"
if [[ $STATUS -ne 0 ]] || printf '%s\n' "$OUTPUT" | grep -qE "$ERROR_PATTERN"; then
	echo "Scene smoke suite failed." >&2
	exit 1
fi
