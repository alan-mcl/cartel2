#!/usr/bin/env bash
#
# Serve dist/web for local Web export testing (not file://).
#
#   ./scripts/ci/serve_web.sh
#   ./scripts/ci/serve_web.sh --port 9080
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEB_ROOT="$ROOT/dist/web"
HOST="127.0.0.1"
PORT="8060"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--port)
			shift
			PORT="${1:?--port requires a value}"
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

if [[ ! -f "$WEB_ROOT/index.html" ]]; then
	echo "ERROR: $WEB_ROOT/index.html not found — run ./scripts/ci/export.sh --web first" >&2
	exit 1
fi

URL="http://${HOST}:${PORT}/"
echo "Serving $WEB_ROOT at $URL"
echo "Open in a browser (Web export does not work from file://)."
cd "$WEB_ROOT"
exec python3 -m http.server "$PORT" --bind "$HOST"