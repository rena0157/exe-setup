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
for profile in core full; do
  HOME="$tmp" USER="${USER:-$(id -un)}" "$ROOT/setup.sh" --dry-run --profile "$profile" --no-shell-change --with-ai >"$tmp/output"
  grep -q 'dry run complete; no changes made' "$tmp/output"
  [[ $(find "$tmp" -mindepth 1 ! -name output -print -quit) == '' ]]
done

# The VM creator renders a first-boot script that stays within exe.dev's 10 KiB limit.
"$ROOT/exe-new.sh" testbox --dry-run --ref abc123 >"$tmp/newout"
grep -q 'boldsoftware/exeuntu' "$tmp/newout"
grep -q 'ref=abc123' "$tmp/newout"
(( $(wc -c <"$tmp/newout") < 10240 ))

# Every dotfile and system file that setup.sh links or installs must exist in the repo.
for f in zshrc zprofile zsh/p10k.zsh zellij/config.kdl git/ignore etc/sysctl.d/90-dev.conf etc/security/limits.d/90-dev.conf \
         etc/systemd/system.conf.d/90-dev.conf etc/systemd/user.conf.d/90-dev.conf etc/docker/daemon.json etc/apt/apt.conf.d/20auto-upgrades \
         backup/backup.sh backup/excludes backup/restic-env.example \
         systemd/user/brew-upgrade.service systemd/user/brew-upgrade.timer systemd/user/docker-prune.service systemd/user/docker-prune.timer \
         systemd/user/backup.service systemd/user/backup.timer systemd/user/t3code.service.d/10-exe-setup-path.conf; do
  [[ -f "$ROOT/$f" ]] || { echo "missing $f" >&2; exit 1; }
done
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$ROOT/etc/docker/daemon.json"

# Manifests are intentionally simple and duplicate-free.
packages=$(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/apt-packages.txt")
[[ -n "$packages" ]]
[[ $(printf '%s\n' "$packages" | sort | uniq -d) == '' ]]
formulas=$(awk -F'"' '/^brew "/ {print $2}' "$ROOT/Brewfile")
[[ -n "$formulas" ]]
[[ $(printf '%s\n' "$formulas" | sort | uniq -d) == '' ]]

# Hermes is never installed by this repository.
if grep -rqi 'hermes' "$ROOT/Brewfile" "$ROOT/apt-packages.txt"; then echo "hermes must not be in the manifests" >&2; exit 1; fi
if grep -Eq 'install.*hermes' "$ROOT/setup.sh"; then echo "setup.sh must not install hermes" >&2; exit 1; fi

echo "tests passed"
