#!/usr/bin/env bash
# Shared helpers for Cartel CI scripts. Source from scripts under scripts/ci/.

set -euo pipefail

: "${ROOT:?ROOT must be set before sourcing lib.sh}"
: "${GODOT:?GODOT must be set before sourcing lib.sh}"

# Godot can exit 0 on parse errors; grep output for these markers.
export CARTEL_ERROR_PATTERN="${CARTEL_ERROR_PATTERN:-SCRIPT ERROR|Parse Error|Failed to load script}"

ci_time_start() {
	_CI_TIME_START="${_CI_TIME_START:-$(date +%s)}"
}

ci_elapsed_sec() {
	local now
	now=$(date +%s)
	echo $((now - _CI_TIME_START))
}

ci_print_stage_time() {
	local label="$1"
	echo "== ${label} ($(ci_elapsed_sec)s) =="
}

# Run a headless Godot script; stream output to the terminal and a temp log; fail on error markers.
# Optional third argument: extra grep pattern (e.g. SMOKE FAIL) joined with OR to CARTEL_ERROR_PATTERN.
ci_run_godot_script() {
	local stage_label="$1"
	local script_path="$2"
	local extra_pattern="${3:-}"
	local log_file
	log_file=$(mktemp)
	trap "rm -f \"$log_file\"" EXIT
	set +e
	local pattern="$CARTEL_ERROR_PATTERN"
	if [[ -n "$extra_pattern" ]]; then
		pattern="$pattern|$extra_pattern"
	fi
	local exit_code=0
	"$GODOT" --headless --path "$ROOT" --script "$script_path" 2>&1 | tee "$log_file"
	exit_code=${PIPESTATUS[0]}
	set -e
	if grep -qE "$pattern" "$log_file"; then
		echo "${stage_label}: output matched error pattern." >&2
		return 1
	fi
	if [[ $exit_code -ne 0 ]]; then
		echo "${stage_label}: exited $exit_code." >&2
		return 1
	fi
	trap - EXIT
	rm -f "$log_file"
	return 0
}
