#!/usr/bin/env bash
# Format check, lint, type check and tests. Run before opening a PR: CI runs the same.
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=.luau-lsp/globalTypes.d.luau
if [ ! -f "$DEFS" ]; then
	mkdir -p .luau-lsp
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== Format"
stylua --check src tests .lune

echo "== Lint"
selene src tests .lune

echo "== Types"
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json src tests

echo "== Tests"
lune run test

echo "All checks passed."
