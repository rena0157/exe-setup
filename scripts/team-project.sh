#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"
identity="$HOME/.config/team-dev/identity.json"
code=$(jq -er .code "$identity")
[[ "$code" =~ ^(JW|LP|MM|DL)$ ]] || { echo 'Unknown developer code' >&2; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
printf 'GitHub identity: '
gh api user --jq .login
repo="$HOME/src/app.caivanos"
if [[ ! -d "$repo" ]]; then
  mkdir -p "$HOME/src"
  gh repo clone abicbuilds/app.caivanos "$repo"
  if [[ -n ${1:-} ]]; then
    [[ "$1" =~ ^[0-9a-f]{40}$ ]] || exit 2
    git -C "$repo" fetch origin "$1"
    git -C "$repo" switch -c "tooling/onboarding-$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')" "$1"
  else
    git -C "$repo" switch -c "tooling/onboarding-$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')"
  fi
fi
cd "$repo"
branch=$(git branch --show-current)
[[ -n "$branch" && "$branch" != main ]] || { echo 'Select a feature branch before onboarding' >&2; exit 1; }
expected=$(jq -r '.packageManager | sub("^bun@"; "")' package.json)
[[ $(bun --version) == "$expected" ]] || { echo "Install Bun $expected before continuing" >&2; exit 1; }
bun install --frozen-lockfile
bun run env init
python3 - <<'PY'
import json, os
from pathlib import Path
identity = json.loads((Path.home()/'.config/team-dev/identity.json').read_text())
path = Path('.caivanos/local.json')
values = json.loads(path.read_text())
values.update(PUBLIC_BASE_URL=f"https://{identity['vm']}.exe.xyz", EMAIL_DELIVERY_MODE='redirect', EMAIL_DEV_REDIRECT_TO=identity['email'])
os.chmod(path, 0o600)
path.write_text(json.dumps(values, indent=2)+'\n')
PY
bun run env up
bun run env doctor
printf '\nProject configured. Authenticate codex and claude in T3, then run bun run dev exe.\n'
