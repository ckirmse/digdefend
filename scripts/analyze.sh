#!/usr/bin/env bash
# Static type analysis via luau-lsp (installed by foreman; see foreman.toml).
# Usage: scripts/analyze.sh [extra luau-lsp analyze args / specific files]
#
# Uses analysis.project.json so one sourcemap covers both places. The goal is
# zero diagnostics in src/, excluding the colon-method self-inference class
# (see CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE_DIR=.luau-analyze
TYPES="$CACHE_DIR/globalTypes.d.luau"
# Pinned to the luau-lsp release we install via foreman.
TYPES_URL="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.69.0/scripts/globalTypes.d.luau"

mkdir -p "$CACHE_DIR"
if [ ! -s "$TYPES" ]; then
    echo "Downloading globalTypes.d.luau..." >&2
    curl -sfL -o "$TYPES" "$TYPES_URL"
fi

python3 scripts/regen_shared_stubs.py >&2
rojo sourcemap analysis.project.json -o sourcemap.json

exec luau-lsp analyze \
    --flag:LuauSolverV2=true \
    --definitions="$TYPES" \
    --sourcemap=sourcemap.json \
    --base-luaurc=.luaurc \
    --ignore "Packages/**" \
    --ignore "DevPackages/**" \
    --ignore "game/**" \
    "${@:-src/}"
