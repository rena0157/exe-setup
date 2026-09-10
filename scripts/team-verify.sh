#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
eval "$(mise activate bash)"
"$HOME/.local/share/exe-setup/scripts/doctor.sh" --profile full
systemctl --user is-active --quiet t3code.service
gh auth status
codex login status
claude auth status
exe-t3 connect status
cd "$HOME/src/app.caivanos"
[[ $(git branch --show-current) != main && -n $(git branch --show-current) ]] || exit 1
bun run env doctor
bun run check
bun run test scripts/commandModules.test.ts scripts/development
bun run build
printf '\nVerify from the developer client: T3 works after reboot; both agents run; private app login and live reload work; another user is denied; a PR uses the developer identity.\n'
read -r -p 'Have ALL client checks above passed? Type verified: ' answer
[[ "$answer" == verified ]] || { echo 'Acceptance remains pending'; exit 1; }
umask 077
mkdir -p "$HOME/.local/state/team-dev"
printf '{"verifiedAt":"%s","appCommit":"%s"}\n' "$(date -u +%FT%TZ)" "$(git rev-parse HEAD)" > "$HOME/.local/state/team-dev/acceptance.json"
echo 'Ready: machine checks and developer acceptance completed.'
