#!/usr/bin/env bash
# Headless unit tests (tests/run.gd). Extra args after -- are forwarded to Godot as user args.
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

user_args=()
while [[ $# -gt 0 ]]; do
	if [[ "$1" == "--" ]]; then
		shift
		while [[ $# -gt 0 ]]; do
			user_args+=("$1")
			shift
		done
		break
	fi
	user_args+=("$1")
	shift
done

cmd=("$GODOT" --headless --path "$ROOT" --script res://tests/run.gd)
if [[ ${#user_args[@]} -gt 0 ]]; then
	cmd+=(--)
	cmd+=("${user_args[@]}")
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
set +e
"${cmd[@]}" 2>&1 | tee "$log"
exit_code=${PIPESTATUS[0]}
set -e
if grep -qE "$CARTEL_ERROR_PATTERN|FAIL:" "$log"; then
	echo "Unit tests failed (script errors or FAIL lines)." >&2
	exit 1
fi
if [[ $exit_code -ne 0 ]]; then
	echo "Unit test runner exited $exit_code." >&2
	exit 1
fi
