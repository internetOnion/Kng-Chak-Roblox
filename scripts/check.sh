#!/usr/bin/env bash
# Format check, lint and type check. Run before opening a PR: all three must pass.
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=.luau-lsp/globalTypes.d.luau
if [ ! -f "$DEFS" ]; then
	mkdir -p .luau-lsp
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

rojo sourcemap default.project.json -o sourcemap.json
stylua --check src
selene src
luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=.luaurc src
echo "All checks passed."
