#!/usr/bin/env bash
# Create an exe.dev VM from the exeuntu image and run exe-setup on first boot.
# Usage: ./exe-new.sh <name> [--cpu N] [--memory SIZE] [--disk SIZE] [--ref GIT_REF] [--core] [--no-ai] [--dry-run]
set -Eeuo pipefail

NAME=""; CPU=16; MEMORY=64GB; DISK=250GB; REF="main"; PROFILE=full; WITH_AI="--with-ai"; DRY_RUN=0
IMAGE="${EXE_IMAGE:-ghcr.io/boldsoftware/exeuntu}"
REPO_URL="${EXE_SETUP_REPO:-https://github.com/rena0157/exe-setup.git}"

usage() { sed -n '2,3p' "$0" | sed 's/^# //'; }
while (($#)); do
  case "$1" in
    --cpu) CPU=$2; shift 2 ;;
    --memory) MEMORY=$2; shift 2 ;;
    --disk) DISK=$2; shift 2 ;;
    --ref) REF=$2; shift 2 ;;
    --core) PROFILE=core; shift ;;
    --no-ai) WITH_AI=""; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) NAME=$1; shift ;;
  esac
done
[[ -n "$NAME" ]] || { usage >&2; exit 1; }

# The first-boot script runs once as the login user via exe-setup.service (exeuntu). It must stay under 10 KiB.
firstboot=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail
export HOME=/home/exedev
exec >>"\$HOME/exe-setup-firstboot.log" 2>&1
echo "=== exe-setup first boot \$(date -Is) ref=$REF profile=$PROFILE"
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates git
DEST="\$HOME/.local/share/exe-setup"
if [ ! -d "\$DEST/.git" ]; then git clone "$REPO_URL" "\$DEST"; fi
# Branches, tags, and full commit SHAs can be fetched directly; abbreviated SHAs cannot.
if ! git -C "\$DEST" fetch --tags origin "$REF"; then
  echo "could not fetch ref $REF; refusing to run an unpinned setup"; exit 1
fi
git -C "\$DEST" checkout --detach FETCH_HEAD
mkdir -p "\$HOME/src"
"\$DEST/setup.sh" --profile "$PROFILE" $WITH_AI || echo "setup.sh exited \$?"
echo "=== first boot finished \$(date -Is)"
EOF
)

cmd=(ssh exe.dev new --name "$NAME" --image "$IMAGE" --cpu "$CPU" --memory "$MEMORY" --disk "$DISK" --tag dev --no-email --setup-script /dev/stdin)
if (( DRY_RUN )); then
  printf 'Would run:'; printf ' %q' "${cmd[@]}"; printf '\n--- setup script ---\n%s\n' "$firstboot"; exit 0
fi
printf '%s\n' "$firstboot" | "${cmd[@]}"
cat <<EOF

VM requested. First boot runs exe-setup in the background; follow it with:
  ssh $NAME.exe.xyz tail -f exe-setup-firstboot.log
Then finish the authentication checklist in README.md (gh auth login, tailscale up, atuin login, restic env).
EOF
