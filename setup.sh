#!/usr/bin/env bash
# exe-setup — bootstrap a fresh exe.dev / Ubuntu-like VM into a coding box.
# Prerequisite: Homebrew already installed.
# Idempotent: safe to re-run.

set -euo pipefail

# ---------- Pretty output ----------
if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED= GREEN= YELLOW= BLUE= BOLD= RESET=
fi
log()  { printf '%s\n' "${BLUE}${BOLD}==>${RESET} ${BOLD}$*${RESET}"; }
ok()   { printf '%s\n' "  ${GREEN}OK${RESET} $*"; }
warn() { printf '%s\n' "  ${YELLOW}!!${RESET} $*"; }
err()  { printf '%s\n' "  ${RED}XX${RESET} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Git identity is resolved at runtime: env var > existing git config > interactive prompt.
# Override either by exporting GIT_NAME / GIT_EMAIL before running.
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
NVIM_CONFIG_REPO="${NVIM_CONFIG_REPO:-https://github.com/rena0157/lazy.nvim.git}"

resolve_git_identity() {
  log "Resolving git identity"
  if [ -z "$GIT_NAME" ]; then
    GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
  fi
  if [ -z "$GIT_EMAIL" ]; then
    GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"
  fi
  if [ -z "$GIT_NAME" ]; then
    read -r -p "  Git user.name:  " GIT_NAME
  fi
  if [ -z "$GIT_EMAIL" ]; then
    read -r -p "  Git user.email: " GIT_EMAIL
  fi
  ok "$GIT_NAME <$GIT_EMAIL>"
}

# ---------- Homebrew ----------
# Source brew into the current shell if it's installed in a known location.
source_brew_if_present() {
  command -v brew >/dev/null 2>&1 && return 0
  for p in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$p" ]; then
      eval "$("$p" shellenv)"
      return 0
    fi
  done
  return 1
}

ensure_brew() {
  log "Ensuring Homebrew is installed"
  if source_brew_if_present; then
    ok "found: $(brew --version | head -1)"
    return
  fi

  # apt-based deps (Debian/Ubuntu). Skip silently on other OSes (e.g. macOS).
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing apt prerequisites"
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential procps curl file git ca-certificates
  fi

  log "Running Homebrew installer (non-interactive)"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if ! source_brew_if_present; then
    err "Homebrew install completed but brew is still not on PATH"; exit 1
  fi
  ok "installed: $(brew --version | head -1)"
}

# ---------- Brew packages ----------
install_brew_packages() {
  log "Installing brew packages"
  local pkgs=(
    zsh
    ripgrep fd eza ast-grep bat fzf zoxide git-delta
    jq yq gh btop
    neovim fnm
    unzip wget
  )
  brew install "${pkgs[@]}"
  ok "core packages installed"

  if ! command -v bun >/dev/null 2>&1; then
    log "Installing bun (oven-sh tap — no core formula on Linux)"
    if ! brew install oven-sh/bun/bun; then
      warn "tap install failed; falling back to bun.sh install script"
      curl -fsSL https://bun.sh/install | bash
      export BUN_INSTALL="$HOME/.bun"
      export PATH="$BUN_INSTALL/bin:$PATH"
    fi
  fi
  if command -v bun >/dev/null 2>&1; then
    ok "bun $(bun --version)"
  else
    err "bun install failed via both paths"
    return 1
  fi
}

# ---------- oh-my-zsh ----------
install_oh_my_zsh() {
  log "Installing oh-my-zsh"
  if [ -d "$HOME/.oh-my-zsh" ]; then
    ok "already installed"
    return
  fi
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  ok "cloned"
}

# ---------- Default shell ----------
set_default_shell() {
  log "Setting default shell to zsh"
  local brew_zsh; brew_zsh="$(brew --prefix)/bin/zsh"
  if [ ! -x "$brew_zsh" ]; then
    err "zsh not found at $brew_zsh"; return 1
  fi
  if ! grep -qxF "$brew_zsh" /etc/shells; then
    echo "$brew_zsh" | sudo tee -a /etc/shells >/dev/null
    ok "added $brew_zsh to /etc/shells"
  fi
  local current; current="$(getent passwd "$USER" | awk -F: '{print $NF}')"
  if [ "$current" != "$brew_zsh" ]; then
    sudo chsh -s "$brew_zsh" "$USER"
    ok "chsh -> $brew_zsh"
  else
    ok "already $brew_zsh"
  fi
}

# ---------- .zshrc ----------
install_zshrc() {
  log "Installing .zshrc"
  local target="$HOME/.zshrc"
  local src="$SCRIPT_DIR/zshrc"
  if [ ! -f "$src" ]; then
    err "Missing $src"; return 1
  fi
  if [ -f "$target" ] && ! diff -q "$src" "$target" >/dev/null 2>&1; then
    local backup="$target.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$backup"
    warn "backed up existing .zshrc -> $backup"
  fi
  cp "$src" "$target"
  ok ".zshrc written"
}

# ---------- Node via fnm ----------
install_node() {
  log "Installing Node LTS via fnm"
  eval "$(fnm env --shell bash)"
  # fnm install errors if already present; tolerate and continue.
  fnm install --lts 2>&1 | grep -v "already installed" || true
  fnm default  lts-latest >/dev/null 2>&1 || true
  fnm use      lts-latest >/dev/null 2>&1 || true
  if command -v node >/dev/null 2>&1; then
    ok "node $(node --version) / npm $(npm --version)"
  else
    err "node not on PATH after fnm install"
    return 1
  fi
}

# ---------- Neovim config ----------
install_nvim_config() {
  log "Installing Neovim config"
  local target="$HOME/.config/nvim"
  mkdir -p "$HOME/.config"
  if [ -d "$target/.git" ]; then
    ok "config already present at $target"
  elif [ -d "$target" ]; then
    warn "$target exists and is not a git repo — leaving alone. Move/remove it manually to re-clone."
  else
    git clone "$NVIM_CONFIG_REPO" "$target"
    ok "cloned to $target"
  fi
  log "Syncing nvim plugins (headless, may take a minute)"
  local attempt
  for attempt in 1 2; do
    if nvim --headless "+Lazy! sync" +qa; then
      ok "plugins synced"
      return
    fi
    warn "Lazy sync attempt $attempt failed"
  done
  warn "plugins not fully synced; run 'nvim +Lazy sync' manually"
}

# ---------- Git config ----------
configure_git() {
  log "Configuring git"
  git config --global user.name  "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global core.pager "delta"
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.line-numbers true
  git config --global delta.syntax-theme "Monokai Extended"
  git config --global merge.conflictstyle "zdiff3"
  git config --global pull.rebase true
  git config --global push.autoSetupRemote true
  ok "git identity: $GIT_NAME <$GIT_EMAIL>"
}

# ---------- SSH key ----------
generate_ssh_key() {
  log "Ensuring ed25519 SSH key"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  if [ -f "$HOME/.ssh/id_ed25519" ]; then
    ok "key already exists"
  else
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N "" -q
    ok "generated"
  fi
  printf '\n%s\n' "${BOLD}GitHub public key (add at https://github.com/settings/keys):${RESET}"
  cat "$HOME/.ssh/id_ed25519.pub"
  echo
}

# ---------- Smoke test ----------
smoke_test() {
  log "Smoke test"
  local cmds=(zsh nvim bun rg fd eza bat fzf zoxide ast-grep delta jq yq gh btop fnm git)
  local missing=0
  for c in "${cmds[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then
      ok "$c"
    else
      err "$c MISSING"; missing=$((missing+1))
    fi
  done
  # node/npm need fnm env loaded
  eval "$(fnm env --shell bash)" 2>/dev/null || true
  for c in node npm; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c $($c --version)"; else err "$c MISSING"; missing=$((missing+1)); fi
  done
  if [ "$missing" -gt 0 ]; then
    err "$missing tool(s) missing"; return 1
  fi
}

main() {
  ensure_brew
  resolve_git_identity
  install_brew_packages
  install_oh_my_zsh
  set_default_shell
  install_zshrc
  install_node
  install_nvim_config
  configure_git
  generate_ssh_key
  smoke_test
  echo
  printf '%s\n' "${GREEN}${BOLD}Setup complete.${RESET} Start a new shell or run: ${BOLD}exec zsh -l${RESET}"
}

main "$@"
