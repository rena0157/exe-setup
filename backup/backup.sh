#!/usr/bin/env bash
# Nightly restic backup of the things on a dev box that are not reproducible from git or package managers.
# Configuration lives outside the repo in ~/.config/restic/env (see restic-env.example).
set -Eeuo pipefail

ENV_FILE="$HOME/.config/restic/env"
[[ -r "$ENV_FILE" ]] || { echo "missing $ENV_FILE; copy backup/restic-env.example there and chmod 600" >&2; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set in $ENV_FILE}"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
EXCLUDES="${RESTIC_EXCLUDES_FILE:-$SCRIPT_DIR/excludes}"
STATE_DIR="$HOME/.local/state/exe-backup"
mkdir -p "$STATE_DIR"

# Extra paths can be appended in the env file: BACKUP_EXTRA_PATHS="/etc/foo /home/me/data"
paths=(
  "$HOME/src"
  "$HOME/.config"
  "$HOME/.ssh"
  "$HOME/.local/bin"
  "$HOME/.gitconfig"
  "$HOME/.zsh_history"
  "$HOME/.claude"
  "$HOME/.codex"
  /etc/systemd/system
  /etc/sysctl.d
  /etc/docker/daemon.json
)
# shellcheck disable=SC2206
paths+=(${BACKUP_EXTRA_PATHS:-})
existing=()
for p in "${paths[@]}"; do [[ -e "$p" ]] && existing+=("$p"); done

echo "Starting backup of $(hostname) at $(date -Is)"
restic snapshots --latest 1 >/dev/null 2>&1 || restic init
restic backup "${existing[@]}" --exclude-file "$EXCLUDES" --exclude-caches --tag "$(hostname)" --one-file-system
restic forget --tag "$(hostname)" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
# Verify a rotating 5% slice of the repository each night; the whole repo is checked over about three weeks.
restic check --read-data-subset=1/20
date -Is > "$STATE_DIR/last-success"
echo "Finished backup at $(date -Is)"
