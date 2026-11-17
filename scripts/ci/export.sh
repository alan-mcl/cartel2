#!/usr/bin/env bash
#
# Headless Godot export into dist/ (not part of check.sh).
#
#   ./scripts/ci/export.sh              # Linux + Web
#   ./scripts/ci/export.sh --linux
#   ./scripts/ci/export.sh --web
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"
EXPORT_TEMPLATES="${GODOT_EXPORT_TEMPLATES:-$HOME/.local/share/godot/export_templates}"

PRESET_LINUX="Linux"
PRESET_WEB="Web"
RUN_LINUX=1
RUN_WEB=1

usage() {
	sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--linux)
			RUN_WEB=0
			;;
		--web)
			RUN_LINUX=0
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "ERROR: unknown argument '$1'" >&2
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

if [[ ! -f "$ROOT/export_presets.cfg" ]]; then
	echo "ERROR: missing $ROOT/export_presets.cfg" >&2
	exit 1
fi

GODOT_LINE="$("$GODOT" --version 2>/dev/null | head -n 1 || true)"
GODOT_VERSION_TAG="$(sed -E 's/\.official.*$//; s/\.custom.*$//' <<<"${GODOT_LINE%% *}")"
TEMPLATE_DIR="$EXPORT_TEMPLATES/$GODOT_VERSION_TAG"

if [[ ! -f "$TEMPLATE_DIR/linux_release.x86_64" ]] || [[ ! -f "$TEMPLATE_DIR/web_release.zip" ]]; then
	echo "ERROR: export templates missing at $TEMPLATE_DIR" >&2
	echo "Install Godot export templates for $GODOT_LINE, e.g.:" >&2
	echo "  mkdir -p \"$EXPORT_TEMPLATES/$GODOT_VERSION_TAG\"" >&2
	echo "  unzip Godot_${GODOT_VERSION_TAG}_export_templates.tpz -d /tmp/godot-export-tp" >&2
	echo "  mv /tmp/godot-export-tp/templates/* \"$EXPORT_TEMPLATES/$GODOT_VERSION_TAG/\"" >&2
	echo "Godot expects versioned paths like .../export_templates/$GODOT_VERSION_TAG/linux_release.x86_64" >&2
	exit 1
fi

echo "Godot:     $GODOT_LINE"
echo "Templates: $TEMPLATE_DIR"

mkdir -p "$ROOT/dist/linux" "$ROOT/dist/web"

run_export() {
	local preset="$1"
	local label="$2"
	echo "== Export $label ($preset) =="
	local log_file
	log_file=$(mktemp)
	trap 'rm -f "$log_file"' RETURN
	set +e
	"$GODOT" --headless --path "$ROOT" --export-release "$preset" 2>&1 | tee "$log_file"
	local exit_code=${PIPESTATUS[0]}
	set -e
	if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Project export for preset|Export failed|Cannot export project' "$log_file"; then
		echo "ERROR: $label export failed (see output above)" >&2
		return 1
	fi
	if [[ $exit_code -ne 0 ]]; then
		echo "ERROR: $label export exited $exit_code" >&2
		return 1
	fi
	trap - RETURN
	rm -f "$log_file"
}

if [[ $RUN_LINUX -eq 1 ]]; then
	run_export "$PRESET_LINUX" "Linux"
	test -f "$ROOT/dist/linux/Cartel.x86_64"
fi

if [[ $RUN_WEB -eq 1 ]]; then
	run_export "$PRESET_WEB" "Web"
	test -f "$ROOT/dist/web/index.html"
fi

echo "Export complete under dist/"