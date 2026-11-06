#!/usr/bin/env bash
#
# Cartel verification script.
#
#   ./scripts/ci/check.sh                    full check (default) - run before marking work done
#   ./scripts/ci/check.sh --fast             validators + unit tests, no import or script sweep
#   ./scripts/ci/check.sh --scripts-only     import + GDScript parse sweep
#   ./scripts/ci/check.sh --tests-only       unit tests only (no smokes)
#   ./scripts/ci/check.sh --suite TestCombat  run only named test class (repeatable)
#
# Stages: [scripts/ci/validators.sh](validators.sh), [scripts/ci/sweep.sh](sweep.sh) (import + parse),
# [scripts/ci/tests.sh](tests.sh), [scripts/ci/smoke_scenes.sh](smoke_scenes.sh).
#
# Godot exits 0 even when a script has parse errors, so Godot steps grep output for error markers.
# Do not pair --check-only with --debug (the interactive debugger can hang).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"

RUN_VALIDATORS=1
RUN_IMPORT=1
RUN_SWEEP=1
RUN_TESTS=1
RUN_SMOKES=1
SUITE_ARGS=()

usage() {
	sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
			RUN_SMOKES=0
			;;
		--tests-only)
			RUN_VALIDATORS=0
			RUN_IMPORT=0
			RUN_SWEEP=0
			RUN_SMOKES=0
			;;
		--suite)
			shift
			if [[ $# -eq 0 ]]; then
				echo "ERROR: --suite requires a class name" >&2
				exit 2
			fi
			SUITE_ARGS+=("--suite" "$1")
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

# shellcheck source=scripts/ci/lib.sh
source "$ROOT/scripts/ci/lib.sh"

if [[ $RUN_VALIDATORS -eq 1 ]]; then
	SECONDS=0
	bash "$ROOT/scripts/ci/validators.sh"
	echo "== Validators (${SECONDS}s) =="
fi

if [[ $RUN_IMPORT -eq 1 ]]; then
	SECONDS=0
	bash "$ROOT/scripts/ci/import.sh"
	echo "== Godot import (${SECONDS}s) =="
fi

if [[ $RUN_SWEEP -eq 1 ]]; then
	SECONDS=0
	bash "$ROOT/scripts/ci/sweep.sh"
	echo "== GDScript parse sweep (${SECONDS}s) =="
fi

if [[ $RUN_TESTS -eq 1 ]]; then
	SECONDS=0
	if [[ ${#SUITE_ARGS[@]} -gt 0 ]]; then
		bash "$ROOT/scripts/ci/tests.sh" -- "${SUITE_ARGS[@]}"
	else
		bash "$ROOT/scripts/ci/tests.sh"
	fi
	echo "== Unit tests (${SECONDS}s) =="
fi

if [[ $RUN_SMOKES -eq 1 ]]; then
	SECONDS=0
	bash "$ROOT/scripts/ci/smoke_scenes.sh"
	echo "== Scene smoke suite (${SECONDS}s) =="
fi

echo "All checks passed."
