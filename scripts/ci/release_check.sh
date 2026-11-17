#!/usr/bin/env bash
#
# Gate for a labelled source-tag release. Does not commit, tag, or edit files.
#
#   ./scripts/ci/release_check.sh --version 1.0.0
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-$HOME/opt/Godot_v4.7.2-stable_linux.x86_64}"

VERSION=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--version)
			shift
			if [[ $# -eq 0 ]]; then
				echo "ERROR: --version requires a value" >&2
				exit 2
			fi
			VERSION="$1"
			;;
		-h|--help)
			sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			echo "ERROR: unknown argument '$1'" >&2
			exit 2
			;;
	esac
	shift
done

if [[ -z "$VERSION" ]]; then
	echo "ERROR: pass --version X.Y.Z" >&2
	exit 2
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "ERROR: version must be numeric semver (X.Y.Z), got '$VERSION'" >&2
	exit 2
fi

if [[ "$VERSION" == "DEV" ]]; then
	echo "ERROR: release version cannot be DEV" >&2
	exit 2
fi

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot not found at $GODOT (set GODOT env var)" >&2
	exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "ERROR: not a git repository" >&2
	exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
	echo "ERROR: working tree is not clean (commit or stash changes first)" >&2
	git status --short >&2
	exit 1
fi

read_version_from_gd() {
	local line
	line=$(grep -E '^\s*const VERSION := ' "$ROOT/scripts/gameplay/game_version.gd" | head -n 1)
	if [[ -z "$line" ]]; then
		echo "ERROR: could not find VERSION in game_version.gd" >&2
		exit 1
	fi
	sed -E 's/.*"([^"]+)".*/\1/' <<<"$line"
}

read_version_from_project() {
	local line
	line=$(grep -E '^config/version=' "$ROOT/project.godot" | head -n 1)
	if [[ -z "$line" ]]; then
		echo "ERROR: could not find config/version in project.godot" >&2
		exit 1
	fi
	sed -E 's/^config\/version="([^"]+)".*/\1/' <<<"$line"
}

GD_VERSION="$(read_version_from_gd)"
PROJ_VERSION="$(read_version_from_project)"

if [[ "$GD_VERSION" == "DEV" ]] || [[ "$PROJ_VERSION" == "DEV" ]]; then
	echo "ERROR: bump GameVersion.VERSION and project.godot config/version to $VERSION before release check" >&2
	echo "  game_version.gd: $GD_VERSION" >&2
	echo "  project.godot:   $PROJ_VERSION" >&2
	exit 1
fi

if [[ "$GD_VERSION" != "$VERSION" ]]; then
	echo "ERROR: game_version.gd VERSION is '$GD_VERSION', expected '$VERSION'" >&2
	exit 1
fi

if [[ "$PROJ_VERSION" != "$VERSION" ]]; then
	echo "ERROR: project.godot config/version is '$PROJ_VERSION', expected '$VERSION'" >&2
	exit 1
fi

echo "== Release gate: $VERSION =="
bash "$ROOT/scripts/ci/check.sh"

COMMIT="$(git rev-parse HEAD)"
GODOT_VERSION="$("$GODOT" --version 2>/dev/null | head -n 1 || true)"
RELEASE_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat <<EOF

=== Release manifest ===
version:  $VERSION
commit:   $COMMIT
godot:    $GODOT_VERSION
date_utc: $RELEASE_DATE

Tag when ready: git tag -a v$VERSION -m "Cartel $VERSION"
EOF