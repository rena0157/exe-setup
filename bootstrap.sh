#!/usr/bin/env bash
# Minimal entry point for a blank Ubuntu host. Pin EXE_SETUP_REF for reproducibility.
set -Eeuo pipefail
REPO_URL="${EXE_SETUP_REPO:-https://github.com/rena0157/exe-setup.git}"
REF="${EXE_SETUP_REF:-main}"
DEST="${EXE_SETUP_DIR:-$HOME/.local/share/exe-setup}"

(( EUID != 0 )) || { echo "Run bootstrap as a regular user with sudo access, not as root." >&2; exit 1; }
command -v sudo >/dev/null 2>&1 || { echo "bootstrap.sh requires sudo" >&2; exit 1; }
command -v apt-get >/dev/null 2>&1 || { echo "bootstrap.sh requires Ubuntu/Debian" >&2; exit 1; }
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates git
if [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" fetch --tags origin "$REF"
else
  mkdir -p "$(dirname "$DEST")"
  git clone --no-checkout "$REPO_URL" "$DEST"
  git -C "$DEST" fetch --tags origin "$REF"
fi
# A detached checkout makes a branch, tag, or pinned commit behave consistently.
# Git refuses this operation rather than overwriting local modifications.
git -C "$DEST" checkout --detach FETCH_HEAD
exec "$DEST/setup.sh" "$@"
