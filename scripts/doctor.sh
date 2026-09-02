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
export PATH="$HOME/.local/bin:$PATH"
HAS_SYSTEMD=0; [[ -d /run/systemd/system ]] && HAS_SYSTEMD=1

required=(brew git gh zsh nvim zellij rg fd eza bat fzf zoxide delta jq yq mise node npm go bun uv python atuin direnv lazygit shellcheck)
[[ "$PROFILE" == full ]] && required+=(docker mosh tailscale ssh restic)
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
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then pass "gh authenticated"; else info "gh is not logged in; run: gh auth login"; fi
fi

for link in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.p10k.zsh" "$HOME/.config/zellij/config.kdl"; do
  if [[ -L "$link" ]]; then pass "$(basename "$link") is managed"; else info "$link is not a symlink into exe-setup"; fi
done
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
if [[ -f "$HOME/.config/restic/env" ]]; then
  restic_mode=$(stat -c %a "$HOME/.config/restic/env" 2>/dev/null || stat -f %Lp "$HOME/.config/restic/env")
  if [[ "$restic_mode" == 600 ]]; then pass "restic env permissions"; else fail "restic env permissions are $restic_mode" "run chmod 600 ~/.config/restic/env"; fi
fi

if [[ "$PROFILE" == full ]]; then
  if (( HAS_SYSTEMD )); then pass "systemd is PID 1"
  else fail "systemd" "this image boots without systemd; recreate the VM from boldsoftware/exeuntu"
  fi
  if command -v docker >/dev/null 2>&1; then
    if id -nG "${USER:-$(id -un)}" | tr ' ' '\n' | grep -qx docker; then pass "Docker group membership"
    else fail "Docker group membership" "run sudo usermod -aG docker \$USER, then log out/in"
    fi
    if (( HAS_SYSTEMD )); then
      if systemctl is-active --quiet docker; then pass "Docker daemon running"; else fail "Docker daemon" "run sudo systemctl enable --now docker"; fi
    fi
    if docker compose version >/dev/null 2>&1; then pass "Docker Compose plugin"
    else fail "Docker Compose plugin" "install the docker-compose-v2 package"
    fi
    if docker buildx version >/dev/null 2>&1; then pass "Docker Buildx plugin"
    else fail "Docker Buildx plugin" "install the docker-buildx package"
    fi
    if [[ -f /etc/docker/daemon.json ]] && grep -q max-size /etc/docker/daemon.json; then pass "Docker log rotation"; else info "Docker log rotation not configured; rerun setup"; fi
  fi
  if command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then pass "Tailscale connected ($(tailscale ip -4 2>/dev/null | head -1))"
    else fail "Tailscale" "run sudo tailscale up --ssh"
    fi
    expiry=$(tailscale status --json 2>/dev/null | jq -r '.Self.KeyExpiry // empty' 2>/dev/null)
    [[ -n "$expiry" && "$expiry" != null ]] && info "Tailscale node key expires $expiry; disable key expiry in the admin console for a long-lived dev box"
  fi
  if (( HAS_SYSTEMD )); then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then pass "fstrim.timer enabled"; else fail "fstrim.timer" "run sudo systemctl enable --now fstrim.timer"; fi
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then pass "unattended security upgrades"; else info "unattended-upgrades not active"; fi
    if loginctl show-user "${USER:-$(id -un)}" -p Linger --value 2>/dev/null | grep -qx yes; then pass "user lingering (timers run when logged out)"; else fail "user lingering" "run sudo loginctl enable-linger \$USER"; fi
    for timer in brew-upgrade.timer docker-prune.timer; do
      if systemctl --user is-enabled --quiet "$timer" 2>/dev/null; then pass "$timer"; else fail "$timer" "rerun ./setup.sh"; fi
    done
    if [[ -f "$HOME/.config/systemd/user/t3code.service" ]]; then
      if systemctl --user is-active --quiet t3code.service; then pass "T3 Code service running"
      else fail "T3 Code service" "run: systemctl --user restart t3code.service; tail ~/.t3/userdata/logs/boot-service.log"
      fi
    fi
    if systemctl --user is-enabled --quiet backup.timer 2>/dev/null; then
      pass "backup.timer enabled"
      marker="$HOME/.local/state/exe-backup/last-success"
      if [[ -f "$marker" ]]; then
        age_hours=$(( ( $(date +%s) - $(stat -c %Y "$marker") ) / 3600 ))
        if (( age_hours <= 30 )); then pass "last backup ${age_hours}h ago"; else fail "last backup ${age_hours}h ago" "run: systemctl --user start backup.service; journalctl --user -u backup"; fi
      else info "no backup has completed yet; run: systemctl --user start backup.service"
      fi
    else info "restic backups are not configured (see backup/restic-env.example)"
    fi
  fi
  watches=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)
  if (( watches >= 524288 )); then pass "inotify watches ($watches)"; else fail "inotify watches ($watches)" "rerun setup to install /etc/sysctl.d/90-dev.conf"; fi
  disk_use=$(df --output=pcent / 2>/dev/null | tail -n1 | tr -dc '0-9')
  if [[ -n "$disk_use" ]]; then
    if (( disk_use < 85 )); then pass "root disk ${disk_use}% used"; else fail "root disk ${disk_use}% used" "run ncdu / or docker system prune"; fi
  fi
fi

if (( failures )); then printf '\n%d actionable failure(s).\n' "$failures"; exit 1; fi
printf '\nAll required checks passed.\n'
