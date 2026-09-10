#!/usr/bin/env bash
set -u
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
state="$HOME/.local/state/team-dev"
printf '  Installation: %s\n' "$(cat "$state/install-status" 2>/dev/null || printf unknown)"
if [[ $(cat "$state/install-status" 2>/dev/null) != base-ready ]]; then exit 0; fi
export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"
printf '  T3 service: %s\n' "$(systemctl --user is-active t3code.service)"
printf '  Lingering: %s\n' "$(loginctl show-user "$(id -un)" -p Linger --value)"
if gh auth status >/dev/null 2>&1; then
  printf '  GitHub: authenticated\n'
else
  printf '  GitHub: awaiting developer sign-in\n'
fi
printf '  Connect: use exe-t3 connect status (saved state); verify from the developer client\n'
if [[ -f "$state/acceptance.json" ]]; then
  printf '  Acceptance: recorded; rerun verify after changes\n'
else
  printf '  Acceptance: pending developer sign-ins and end-to-end checks\n'
fi
