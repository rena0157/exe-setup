#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"
version=$(jq -er '.activeVersion | select(test("^[0-9][0-9A-Za-z.+-]*$"))' "$HOME/.t3/runtime/service-state.json")
exec mise exec -- node "$HOME/.t3/runtime/versions/$version/node_modules/t3/dist/bin.mjs" "$@"
