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
T3_NPM_TAG="${T3_NPM_TAG:-nightly}"
MISE_NODE_VERSION="${MISE_NODE_VERSION:-24}"
MISE_GO_VERSION="${MISE_GO_VERSION:-1.26}"
TIMEZONE="${TIMEZONE:-America/Toronto}"

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
  --profile full|core  full configures Docker/Tailscale, system tuning, timers, and an SSH key (default: full)
  --with-ai            install pi, Claude Code, Codex, OpenCode, and the T3 Code service (never Hermes)
  --no-shell-change    do not change the login shell
  --dry-run            print planned actions without changing the host
  --check              run scripts/doctor.sh only
  -h, --help           show this help

Environment:
  GIT_NAME, GIT_EMAIL  explicitly set/replace Git identity (otherwise preserve it)
  NVIM_CONFIG_REPO     Neovim config URL; set to 'none' to use clean defaults
  PI_NPM_PACKAGE       pi package used by --with-ai
  T3_NPM_TAG           npm dist-tag for T3 Code used by --with-ai (default: nightly)
  MISE_NODE_VERSION    global Node version installed by mise (default: 24)
  MISE_GO_VERSION      global Go version installed by mise (default: 1.26)
  TIMEZONE             system timezone for the full profile (default: America/Toronto)
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

# systemd is required for Docker, Tailscale, and the maintenance timers. exe.dev's exeuntu image has it;
# raw OCI images such as ubuntu:26.04 boot with exe-init instead and cannot run those services.
HAS_SYSTEMD=0; [[ -d /run/systemd/system ]] && HAS_SYSTEMD=1

source_brew() {
  command -v brew >/dev/null 2>&1 && return
  local brew
  for brew in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew" ]]; then eval "$("$brew" shellenv)"; return; fi
  done
  return 1
}

# Write a root-owned file only when its content differs. Prints "changed" when it wrote.
install_system_file() {
  local source=$1 target=$2 mode=${3:-0644}
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then ok "$target up to date"; return 1; fi
  run sudo install -D -m "$mode" "$source" "$target"
  return 0
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
  # Minimal container images lack /dev/fd, which the Homebrew installer requires.
  [[ -e /dev/fd ]] || sudo ln -s /proc/self/fd /dev/fd
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  source_brew || die "Homebrew installed but could not be found"
}

install_brew_bundle() {
  log "Homebrew bundle"
  # Recent Homebrew refuses formulae from third-party taps until they are explicitly trusted.
  local tap
  while read -r tap; do
    [[ -n "$tap" ]] || continue
    if (( DRY_RUN )); then run brew trust "$tap"
    elif brew trust --help >/dev/null 2>&1; then
      brew tap "$tap" >/dev/null 2>&1 || true
      brew trust "$tap" >/dev/null 2>&1 || warn "could not trust tap $tap"
    fi
  done < <(awk -F'"' '/^tap "/ {print $2}' "$SCRIPT_DIR/Brewfile")
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
  local -a links=(
    "zshrc:$HOME/.zshrc"
    "zprofile:$HOME/.zprofile"
    "zsh/p10k.zsh:$HOME/.p10k.zsh"
    "zellij/config.kdl:$HOME/.config/zellij/config.kdl"
    "git/ignore:$HOME/.config/git/ignore"
  )
  local entry
  for entry in "${links[@]}"; do
    if (( DRY_RUN )); then run ln -s "$SCRIPT_DIR/${entry%%:*}" "${entry#*:}"
    else backup_and_link "$SCRIPT_DIR/${entry%%:*}" "${entry#*:}"
    fi
  done
  (( DRY_RUN )) && return
  # Reject an invalid managed Zellij config rather than shipping a broken multiplexer.
  if command -v zellij >/dev/null 2>&1; then zellij setup --check >/dev/null || die "Zellij config failed validation"; fi
  mkdir -p "$HOME/.config/shell"
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
fetch.prune=true
rebase.autoStash=true
rerere.enabled=true
diff.algorithm=histogram
branch.sort=-committerdate
column.ui=auto
delta.navigate=true
delta.line-numbers=true
delta.syntax-theme=Monokai Extended
delta.minus-style=syntax "#3a262a"
delta.minus-emph-style=syntax "#5a3034"
delta.plus-style=syntax "#24362b"
delta.plus-emph-style=syntax "#31513b"
delta.line-numbers-minus-style=#b86b77
delta.line-numbers-plus-style=#7fa38a
EOF
  # gh stores the GitHub token; git reuses it instead of a separate PAT or SSH key per machine.
  if [[ -z "$(git config --global --get credential.https://github.com.helper 2>/dev/null || true)" ]]; then
    run git config --global credential.https://github.com.helper '!gh auth git-credential'
    run git config --global credential.https://gist.github.com.helper '!gh auth git-credential'
  fi
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

configure_system() {
  log "System tuning (sysctl, file limits, Docker daemon, timezone)"
  if ! (( HAS_SYSTEMD )); then warn "no systemd on this host; skipping system tuning and services"; return; fi
  install_system_file "$SCRIPT_DIR/etc/sysctl.d/90-dev.conf" /etc/sysctl.d/90-dev.conf && run sudo sysctl -q --system
  install_system_file "$SCRIPT_DIR/etc/security/limits.d/90-dev.conf" /etc/security/limits.d/90-dev.conf || true
  install_system_file "$SCRIPT_DIR/etc/systemd/system.conf.d/90-dev.conf" /etc/systemd/system.conf.d/90-dev.conf || true
  install_system_file "$SCRIPT_DIR/etc/systemd/user.conf.d/90-dev.conf" /etc/systemd/user.conf.d/90-dev.conf || true
  if command -v timedatectl >/dev/null 2>&1; then
    local current_tz; current_tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    if [[ "$current_tz" != "$TIMEZONE" ]]; then run sudo timedatectl set-timezone "$TIMEZONE"; else ok "timezone $TIMEZONE"; fi
  fi
  # Docker: rotate container logs and default to BuildKit so a long-lived dev box does not fill its disk.
  if command -v docker >/dev/null 2>&1; then
    if install_system_file "$SCRIPT_DIR/etc/docker/daemon.json" /etc/docker/daemon.json; then
      run sudo systemctl enable --now docker
      run sudo systemctl restart docker
    else
      run sudo systemctl enable --now docker
    fi
    if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then run sudo usermod -aG docker "$USER"; warn "log out/in to activate Docker group membership"; fi
  fi
  run sudo systemctl enable --now fstrim.timer
  # Security updates apply themselves; feature upgrades stay manual. The exeuntu image masks these units.
  install_system_file "$SCRIPT_DIR/etc/apt/apt.conf.d/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades || true
  if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades; fi
  run sudo systemctl unmask apt-daily.timer apt-daily-upgrade.timer apt-daily.service apt-daily-upgrade.service unattended-upgrades.service
  run sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service
}

install_tailscale() {
  log "Tailscale"
  if ! command -v tailscale >/dev/null 2>&1; then
    if (( DRY_RUN )); then echo "  DRY-RUN: install Tailscale from its official installer"; else curl -fsSL https://tailscale.com/install.sh | sh; fi
  else ok "$(tailscale version | head -1)"
  fi
  if (( HAS_SYSTEMD )); then run sudo systemctl enable --now tailscaled; else warn "no systemd; start tailscaled manually"; fi
  if ! (( DRY_RUN )) && command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then ok "tailscale is up"; else warn "run: sudo tailscale up --ssh   (then disable key expiry for this node in the admin console)"; fi
  fi
}

install_ssh_key() {
  log "SSH key"
  if (( DRY_RUN )); then echo "  DRY-RUN: generate ~/.ssh/id_ed25519 when absent"; return; fi
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then ssh-keygen -q -t ed25519 -N '' -C "${GIT_EMAIL:-$USER@$(hostname)}" -f "$HOME/.ssh/id_ed25519"; fi
  ok "public key: $(cut -d' ' -f1-2 "$HOME/.ssh/id_ed25519.pub")"
}

install_user_services() {
  log "User services: weekly brew upgrade, weekly docker prune, nightly restic backup"
  if ! (( HAS_SYSTEMD )); then warn "no systemd; skipping user timers"; return; fi
  local unit_dir="$HOME/.config/systemd/user"
  if (( DRY_RUN )); then
    run sudo loginctl enable-linger "$USER"
    run install -D -m 0644 "$SCRIPT_DIR"/systemd/user/*.service "$SCRIPT_DIR"/systemd/user/*.timer "$unit_dir/"
    run ln -sf "$SCRIPT_DIR/backup/backup.sh" "$HOME/.local/bin/exe-backup"
    run systemctl --user enable --now brew-upgrade.timer docker-prune.timer backup.timer
    return
  fi
  # Lingering lets user timers run while nobody is logged in.
  loginctl show-user "$USER" -p Linger --value 2>/dev/null | grep -qx yes || sudo loginctl enable-linger "$USER"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  mkdir -p "$unit_dir" "$HOME/.local/bin"
  install -m 0644 "$SCRIPT_DIR"/systemd/user/*.service "$SCRIPT_DIR"/systemd/user/*.timer "$unit_dir/"
  ln -sf "$SCRIPT_DIR/backup/backup.sh" "$HOME/.local/bin/exe-backup"
  systemctl --user daemon-reload
  systemctl --user enable --now brew-upgrade.timer
  if command -v docker >/dev/null 2>&1; then systemctl --user enable --now docker-prune.timer; fi
  if [[ -f "$HOME/.config/restic/env" ]]; then
    systemctl --user enable --now backup.timer; ok "restic backup timer enabled (nightly 03:30)"
  else
    systemctl --user disable --now backup.timer 2>/dev/null || true
    warn "backups not configured: copy backup/restic-env.example to ~/.config/restic/env (chmod 600), then rerun"
  fi
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
  log "Optional AI coding CLIs (pi, Claude Code, Codex, OpenCode, T3 Code; Hermes excluded)"
  if (( DRY_RUN )); then
    run npm install -g "$PI_NPM_PACKAGE" @openai/codex; run brew install opencode; echo "  DRY-RUN: run the official Claude installer"
    run npx -y "t3@$T3_NPM_TAG" service install; return
  fi
  eval "$(mise activate bash)"
  npm install -g "$PI_NPM_PACKAGE" @openai/codex
  brew list opencode >/dev/null 2>&1 || brew install opencode
  command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
  install_t3
}

# T3 Code runs as a per-user systemd service (t3code.service) that self-updates within its channel.
# Remote access (T3 Connect) is an authenticated step left to the checklist: npx t3@nightly connect link --headless
install_t3() {
  if ! (( HAS_SYSTEMD )); then warn "no systemd; skipping the T3 Code service"; return; fi
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if npx -y "t3@$T3_NPM_TAG" service status 2>/dev/null | grep -q 'Status: installed'; then
    if npx -y "t3@$T3_NPM_TAG" service update >/dev/null 2>&1; then ok "T3 Code service updated to the $T3_NPM_TAG channel"
    else warn "T3 Code service update failed; run: npx t3@$T3_NPM_TAG service update"
    fi
  else
    # The installer writes the unit first and then tries `loginctl enable-linger` itself, which fails without
    # polkit in a non-interactive session. Lingering is already on (install_user_services), so finish the job here.
    if npx -y "t3@$T3_NPM_TAG" service install >/dev/null 2>&1; then ok "T3 Code service installed"
    elif [[ -f "$HOME/.config/systemd/user/t3code.service" ]]; then warn "T3 Code installer could not enable lingering itself; enabling the unit directly"
    else warn "T3 Code service install failed; run: npx t3@$T3_NPM_TAG service install"; return
    fi
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now t3code.service >/dev/null 2>&1 || warn "t3code.service did not start; see ~/.t3/userdata/logs/boot-service.log"
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
  if [[ "$PROFILE" == full ]]; then
    configure_system
    install_tailscale
    install_ssh_key
    install_user_services
  fi
  set_shell
  install_ai
  if (( DRY_RUN )); then ok "dry run complete; no changes made"; else "$SCRIPT_DIR/scripts/doctor.sh" --profile "$PROFILE" || warn "doctor found issues; follow its suggestions above"; fi
}
main
