#!/usr/bin/env bash
# Start Rojo for one place. Usage: scripts/serve.sh lobby|gameplay
# Lobby serves on port 34872, Gameplay on 34873 (see servePort in each
# *.project.json); both can run at the same time.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
    lobby|gameplay) ;;
    *) echo "usage: $0 lobby|gameplay" >&2; exit 2 ;;
esac

exec rojo serve "$1.project.json"
