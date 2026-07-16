#!/usr/bin/env bash
# Read-only installation diagnostics.
set -u
PROFILE=full
if [[ ${1:-} == --profile ]]; then PROFILE=${2:-}; shift 2; fi
[[ $# == 0 && ( "$PROFILE" == full || "$PROFILE" == core ) ]] || { echo "Usage: scripts/doctor.sh [--profile full|core]" >&2; exit 2; }

if [ -t 1 ]; then GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'; else GREEN=; RED=; YELLOW=; RESET=; fi
failures=0
pass() { printf '%s\n' "${GREEN}PASS${RESET} $*"; }
fail() { printf '%s\n' "${RED}FAIL${RESET} $1 — $2"; failures=$((failures + 1)); }
info() { printf '%s\n' "${YELLOW}INFO${RESET} $*"; }

# setup.sh normally exposes brew before invoking us; support standalone doctor runs too.
if ! command -v brew >/dev/null 2>&1; then
  for candidate in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then eval "$("$candidate" shellenv)"; break; fi
  done
fi
if command -v mise >/dev/null 2>&1; then eval "$(mise activate bash)"; fi

required=(brew git gh zsh nvim zellij rg fd eza bat fzf zoxide delta jq yq mise node npm go bun uv python)
[[ "$PROFILE" == full ]] && required+=(docker mosh tailscale ssh)
for command_name in "${required[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then pass "$command_name"
  else fail "$command_name" "rerun ./setup.sh --profile $PROFILE"
  fi
done

if [[ -n "$(git config --global user.name 2>/dev/null || true)" && -n "$(git config --global user.email 2>/dev/null || true)" ]]; then
  pass "Git identity configured"
else
  info "Git identity is incomplete; set GIT_NAME and GIT_EMAIL, then rerun setup"
fi

if [[ -f "$HOME/.config/zellij/config.kdl" ]] && command -v zellij >/dev/null 2>&1; then
  if zellij setup --check >/dev/null 2>&1; then pass "Zellij config valid"
  else fail "Zellij config" "run zellij setup --check"
  fi
fi
if [[ -f "$HOME/.config/shell/env" ]]; then
  env_mode=$(stat -c %a "$HOME/.config/shell/env" 2>/dev/null || stat -f %Lp "$HOME/.config/shell/env")
  if [[ "$env_mode" == 600 ]]; then pass "Local environment file permissions"
  else fail "$HOME/.config/shell/env permissions are $env_mode" "run chmod 600 $HOME/.config/shell/env"
  fi
fi
if [[ "$PROFILE" == full ]] && command -v docker >/dev/null 2>&1; then
  if id -nG "${USER:-$(id -un)}" | tr ' ' '\n' | grep -qx docker; then pass "Docker group membership"
  else fail "Docker group membership" "run sudo usermod -aG docker \$USER, then log out/in"
  fi
  if docker compose version >/dev/null 2>&1; then pass "Docker Compose plugin"
  else fail "Docker Compose plugin" "install the docker-compose-v2 package"
  fi
  if docker buildx version >/dev/null 2>&1; then pass "Docker Buildx plugin"
  else fail "Docker Buildx plugin" "install the docker-buildx package"
  fi
fi

if (( failures )); then printf '\n%d actionable failure(s).\n' "$failures"; exit 1; fi
printf '\nAll required checks passed.\n'
