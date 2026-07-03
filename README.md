# exe-setup

Idempotent bootstrap script for a fresh exe.dev / Ubuntu-like VM.

## Usage

```bash
./setup.sh
```

Re-running is safe — every step checks before acting.

## What gets installed

- **Homebrew** (auto-installs if missing; needs `sudo` once for apt prerequisites)
- **Shell**: zsh + oh-my-zsh, made default via `chsh`
- **Terminal multiplexer**: Zellij + managed config at `~/.config/zellij/config.kdl`
- **CLI toolchain**: `ripgrep`, `fd`, `eza`, `ast-grep`, `bat`, `fzf`, `zoxide`, `delta`, `jq`, `yq`, `gh`, `btop`, `zellij`
- **Network tools**: Tailscale (`tailscaled` enabled when systemd is available), `mosh-server`
- **Runtimes**: Node LTS via `fnm`, `bun` (via `oven-sh/bun` tap with a curl-script fallback)
- **Editor**: Neovim + LazyVim config (`Lazy! sync` runs headless)
- **Git** identity + `delta` pager + sane defaults (`pull.rebase`, `push.autoSetupRemote`, `zdiff3`)
- **SSH**: ed25519 keypair (pubkey printed at the end to add to GitHub)

## Git identity resolution

Resolved in this order — first non-empty wins:

1. `GIT_NAME` / `GIT_EMAIL` env vars
2. Existing `git config --global user.name` / `user.email`
3. Interactive prompt

## Overrides

| Env var            | Default                                     |
| ------------------ | ------------------------------------------- |
| `GIT_NAME`         | (prompt)                                    |
| `GIT_EMAIL`        | (prompt)                                    |
| `NVIM_CONFIG_REPO` | `https://github.com/rena0157/lazy.nvim.git` |

## Requirements

- Debian/Ubuntu (uses `apt-get` for Homebrew prerequisites, Tailscale, and mosh-server), or a system with Homebrew already on `PATH`
- Passwordless `sudo` or a willingness to type your password once

## After it finishes

Start a new shell (or `exec zsh -l`) to land in zsh with everything wired.
