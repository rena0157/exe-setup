#!/usr/bin/env bash
# Idempotent Ubuntu development-machine setup. See README.md before running.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
PROFILE=full
CHANGE_SHELL=1
WITH_AI=0
NVIM_CONFIG_REPO="${NVIM_CONFIG_REPO-https://github.com/rena0157/lazy.nvim.git}"
PI_NPM_PACKAGE="${PI_NPM_PACKAGE:-@earendil-works/pi-coding-agent}"
MISE_NODE_VERSION="${MISE_NODE_VERSION:-24}"
MISE_GO_VERSION="${MISE_GO_VERSION:-1.26}"

if [ -t 1 ]; then BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'; else BLUE=; GREEN=; YELLOW=; RED=; BOLD=; RESET=; fi
log() { printf '%s\n' "${BLUE}${BOLD}==>${RESET} $*"; }
ok() { printf '%s\n' "  ${GREEN}OK${RESET} $*"; }
warn() { printf '%s\n' "  ${YELLOW}!!${RESET} $*"; }
die() { printf '%s\n' "  ${RED}XX${RESET} $*" >&2; exit 1; }
quote_cmd() { printf ' %q' "$@"; printf '\n'; }
run() { if (( DRY_RUN )); then printf '  DRY-RUN:'; quote_cmd "$@"; else "$@"; fi; }

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Options:
  --profile full|core  full configures Docker/Tailscale and an SSH key (default: full)
  --with-ai            install pi, Claude Code, and Codex CLIs (never Hermes)
  --no-shell-change    do not change the login shell
  --dry-run            print planned actions without changing the host
  --check              run scripts/doctor.sh only
  -h, --help           show this help

Environment:
  GIT_NAME, GIT_EMAIL  explicitly set/replace Git identity (otherwise preserve it)
  NVIM_CONFIG_REPO     Neovim config URL; set to 'none' to use clean defaults
  PI_NPM_PACKAGE       pi package used by --with-ai
  MISE_NODE_VERSION    global Node version installed by mise (default: 24)
  MISE_GO_VERSION      global Go version installed by mise (default: 1.26)
EOF
}

CHECK=0
while (($#)); do
  case "$1" in
    --profile) (($# >= 2)) || die "--profile needs a value"; PROFILE=$2; shift 2 ;;
    --with-ai) WITH_AI=1; shift ;;
    --no-shell-change) CHANGE_SHELL=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
[[ "$PROFILE" == full || "$PROFILE" == core ]] || die "profile must be 'full' or 'core'"
if (( CHECK )); then exec "$SCRIPT_DIR/scripts/doctor.sh" --profile "$PROFILE"; fi
if (( EUID == 0 )); then die "run setup as a regular user with sudo access, not as root"; fi

source_brew() {
  command -v brew >/dev/null 2>&1 && return
  local brew
  for brew in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew" ]]; then eval "$("$brew" shellenv)"; return; fi
  done
  return 1
}

install_apt() {
  log "APT packages"
  command -v apt-get >/dev/null 2>&1 || die "Ubuntu/Debian with apt-get is required"
  mapfile -t packages < <(grep -Ev '^[[:space:]]*(#|$)' "$SCRIPT_DIR/apt-packages.txt")
  (( DRY_RUN )) && { run sudo apt-get update; run sudo apt-get install -y "${packages[@]}"; return; }
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_brew() {
  log "Homebrew"
  if source_brew; then ok "$(brew --version | head -1)"; return; fi
  if (( DRY_RUN )); then echo "  DRY-RUN: install Homebrew from its official installer"; return; fi
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  source_brew || die "Homebrew installed but could not be found"
}

install_brew_bundle() {
  log "Homebrew bundle"
  (( DRY_RUN )) && { run brew bundle --file "$SCRIPT_DIR/Brewfile"; return; }
  brew bundle --file "$SCRIPT_DIR/Brewfile"
}

backup_and_link() {
  local source=$1 target=$2
  mkdir -p "$(dirname "$target")"
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then ok "$target already linked"; return; fi
  if [[ -e "$target" || -L "$target" ]]; then
    local backup
    backup="${target}.backup.$(date +%Y%m%d-%H%M%S)"
    run mv "$target" "$backup"; warn "preserved existing file as $backup"
  fi
  run ln -s "$source" "$target"
}

install_shell_tools() {
  log "Shell tooling"
  if [[ -d "$HOME/.oh-my-zsh" ]]; then ok "Oh My Zsh already installed"
  else run git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  fi
}

install_dotfiles() {
  log "Dotfiles"
  if (( DRY_RUN )); then
    run ln -s "$SCRIPT_DIR/zshrc" "$HOME/.zshrc"
    run ln -s "$SCRIPT_DIR/zprofile" "$HOME/.zprofile"
    run ln -s "$SCRIPT_DIR/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
    return
  fi
  backup_and_link "$SCRIPT_DIR/zshrc" "$HOME/.zshrc"
  backup_and_link "$SCRIPT_DIR/zprofile" "$HOME/.zprofile"
  backup_and_link "$SCRIPT_DIR/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
  # Preserve the pre-existing validation behavior: reject an invalid managed config.
  if command -v zellij >/dev/null 2>&1; then zellij setup --check >/dev/null || die "Zellij config failed validation"; fi
}

configure_git() {
  log "Git defaults and identity"
  local key value
  while IFS='=' read -r key value; do
    [[ -n "$(git config --global --get "$key" 2>/dev/null || true)" ]] || run git config --global "$key" "$value"
  done <<'EOF'
init.defaultBranch=main
core.pager=delta
interactive.diffFilter=delta --color-only
merge.conflictstyle=zdiff3
pull.rebase=true
push.autoSetupRemote=true
delta.navigate=true
delta.line-numbers=true
delta.syntax-theme=Monokai Extended
EOF
  # Identity is never replaced implicitly. Supplying either variable is explicit consent for that field.
  [[ -z "${GIT_NAME:-}" ]] || run git config --global user.name "$GIT_NAME"
  [[ -z "${GIT_EMAIL:-}" ]] || run git config --global user.email "$GIT_EMAIL"
  [[ -n "$(git config --global user.name 2>/dev/null || true)" ]] || warn "Git user.name unset; export GIT_NAME and rerun"
  [[ -n "$(git config --global user.email 2>/dev/null || true)" ]] || warn "Git user.email unset; export GIT_EMAIL and rerun"
}

install_runtimes() {
  log "Node LTS and Go via mise"
  if (( DRY_RUN )); then run mise use --global "node@$MISE_NODE_VERSION" "go@$MISE_GO_VERSION"; else
    eval "$(mise activate bash)"
    mise use --global "node@$MISE_NODE_VERSION" "go@$MISE_GO_VERSION"
  fi
  log "Python workflow via uv"
  # uv is provided by Brewfile; Python versions/environments remain project-local.
  run uv python install --default
  export PATH="$HOME/.local/bin:$PATH"
}

install_nvim_config() {
  log "Neovim configuration"
  local target="$HOME/.config/nvim"
  if [[ -e "$target" ]]; then ok "leaving existing $target unchanged"
  elif [[ -n "$NVIM_CONFIG_REPO" && "$NVIM_CONFIG_REPO" != none ]]; then run git clone "$NVIM_CONFIG_REPO" "$target"
  else warn "Neovim will use its clean defaults"
  fi
}

install_full_profile() {
  log "Docker, Mosh, and Tailscale"
  # Ubuntu's maintained docker.io package is installed from apt-packages.txt.
  if (( DRY_RUN )); then
    run sudo usermod -aG docker "$USER"
    echo "  DRY-RUN: install Tailscale from its official installer"
    return
  fi
  sudo systemctl enable --now docker 2>/dev/null || warn "Docker service not started (systemd may be unavailable)"
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then sudo usermod -aG docker "$USER"; warn "log out/in to activate Docker group membership"; fi
  if ! command -v tailscale >/dev/null 2>&1; then curl -fsSL https://tailscale.com/install.sh | sh; fi
  sudo systemctl enable --now tailscaled 2>/dev/null || warn "tailscaled not started; run: sudo systemctl enable --now tailscaled"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then ssh-keygen -q -t ed25519 -N '' -C "${GIT_EMAIL:-$USER@$(hostname)}" -f "$HOME/.ssh/id_ed25519"; fi
}

set_shell() {
  (( CHANGE_SHELL )) || { warn "login shell change skipped"; return; }
  local shell
  if (( DRY_RUN )) && ! command -v brew >/dev/null 2>&1; then shell=/home/linuxbrew/.linuxbrew/bin/zsh; else shell="$(brew --prefix)/bin/zsh"; fi
  if (( DRY_RUN )); then run sudo sh -c "grep -qxF '$shell' /etc/shells || echo '$shell' >> /etc/shells"; run chsh -s "$shell"; return; fi
  grep -qxF "$shell" /etc/shells || echo "$shell" | sudo tee -a /etc/shells >/dev/null
  [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$shell" ]] || sudo chsh -s "$shell" "$USER"
}

install_ai() {
  (( WITH_AI )) || return 0
  log "Optional AI coding CLIs (pi, Claude Code, Codex; Hermes excluded)"
  if (( DRY_RUN )); then run npm install -g "$PI_NPM_PACKAGE" @openai/codex; echo "  DRY-RUN: run the official Claude installer"; return; fi
  eval "$(mise activate bash)"
  npm install -g "$PI_NPM_PACKAGE" @openai/codex
  command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
}

main() {
  install_apt
  install_brew
  install_brew_bundle
  install_shell_tools
  install_dotfiles
  configure_git
  install_runtimes
  install_nvim_config
  [[ "$PROFILE" == full ]] && install_full_profile
  set_shell
  install_ai
  if (( DRY_RUN )); then ok "dry run complete; no changes made"; else "$SCRIPT_DIR/scripts/doctor.sh" --profile "$PROFILE" || warn "doctor found issues; follow its suggestions above"; fi
}
main
