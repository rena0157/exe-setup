#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

help="$("$ROOT/setup.sh" --help)"
grep -q -- '--dry-run' <<<"$help"
grep -q -- '--check' <<<"$help"

if "$ROOT/setup.sh" --profile invalid >/dev/null 2>&1; then
  echo "invalid profile unexpectedly succeeded" >&2; exit 1
fi

# A dry run must work with an isolated HOME and must not create anything there.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
HOME="$tmp" USER="${USER:-$(id -un)}" "$ROOT/setup.sh" --dry-run --profile core --no-shell-change >"$tmp/output"
grep -q 'dry run complete; no changes made' "$tmp/output"
[[ $(find "$tmp" -mindepth 1 ! -name output -print -quit) == '' ]]

# Manifests are intentionally simple and duplicate-free.
packages=$(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/apt-packages.txt")
[[ -n "$packages" ]]
[[ $(printf '%s\n' "$packages" | sort | uniq -d) == '' ]]
formulas=$(awk -F'"' '/^brew "/ {print $2}' "$ROOT/Brewfile")
[[ -n "$formulas" ]]
[[ $(printf '%s\n' "$formulas" | sort | uniq -d) == '' ]]

echo "tests passed"
