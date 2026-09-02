# exe-setup

A one-command, idempotent bootstrap for an Ubuntu development machine, tuned for [exe.dev](https://exe.dev) VMs built from the `ghcr.io/boldsoftware/exeuntu` image. `setup.sh` is the orchestrator; `exe-new.sh` creates a VM and runs it on first boot; `bootstrap.sh` installs Git, obtains this repository, and hands off to `setup.sh` on any Ubuntu host. Homebrew's `Brewfile` is the source of truth for global CLI tools, `apt-packages.txt` contains host packages, and everything under `etc/` and `systemd/` is installed verbatim. **Hermes is explicitly excluded**: the agent machine and the development machine are deliberately separate.

## Create a new exe.dev dev machine

```bash
git clone https://github.com/rena0157/exe-setup.git ~/src/exe-setup
cd ~/src/exe-setup
./exe-new.sh ardev                       # 16 vCPU, 64 GB, 250 GB, exeuntu, full profile with AI CLIs
./exe-new.sh scratch --cpu 4 --memory 8GB --disk 40GB --core --no-ai
```

`exe-new.sh` pipes a small first-boot script to `ssh exe.dev new --setup-script`. On first boot the VM clones this repository at `--ref` (default `main`; pin a commit SHA for reproducibility) and runs `setup.sh`, logging to `~/exe-setup-firstboot.log`. Use `--dry-run` to print the exact command and script without creating anything.

The image matters. exeuntu boots systemd, logs you in as `exedev` with passwordless sudo, and ships Docker and Tailscale. A raw OCI image such as `ubuntu:26.04` boots exe.dev's `exe-init` instead: no systemd, root login only, and Docker, Tailscale, mosh, and the timers below cannot run. `doctor.sh` fails loudly on such a host.

## Run it on an existing host

```bash
git clone https://github.com/rena0157/exe-setup.git ~/.local/share/exe-setup
cd ~/.local/share/exe-setup
./setup.sh --with-ai
```

Or, on a blank Ubuntu host without this repository:

```bash
curl -fsSL https://raw.githubusercontent.com/rena0157/exe-setup/main/bootstrap.sh | bash -s -- --with-ai
```

**Security:** `curl | bash` executes mutable remote code without review. Prefer cloning and inspecting it. For automation, set `EXE_SETUP_REF` to a reviewed commit SHA.

## Options

```text
--profile full|core  core skips Docker/Tailscale, system tuning, timers, and SSH key creation
--with-ai            opt in to pi, Claude Code, Codex, and OpenCode (never Hermes)
--no-shell-change    leave the current login shell unchanged
--dry-run            print actions without changing the machine
--check              run the read-only doctor
--help               show command help
```

Environment overrides: `GIT_NAME`, `GIT_EMAIL`, `NVIM_CONFIG_REPO`, `PI_NPM_PACKAGE`, `MISE_NODE_VERSION` (24), `MISE_GO_VERSION` (1.26), `TIMEZONE` (America/Toronto).

## What you get

- **Packages.** Ubuntu packages from `apt-packages.txt` (build tools, Docker Engine with Compose and Buildx, mosh, rsync, network utilities). Global CLIs from `Brewfile`: zsh, gh, git-delta, git-lfs, lazygit, Neovim, Zellij, mise, uv, Bun, ripgrep, fd, eza, bat, fzf, zoxide, atuin, direnv, ast-grep, jq, yq, ncdu, btop, mkcert, cloudflared, restic, shellcheck, shfmt.
- **Shell.** Oh My Zsh with powerlevel10k (`zsh/p10k.zsh`), autosuggestions, syntax highlighting, fzf keybindings, zoxide as `cd`, atuin history, direnv, and the `ls`/`cat`/`g`/`lg`/`dc` aliases. Interactive SSH logins auto-attach to a Zellij session named `main`; opt out per session with `ZELLIJ_AUTO_ATTACH=0` or permanently with `touch ~/.config/shell/no-zellij`.
- **Runtimes.** Node 24 and Go 1.26 via mise (project `.mise.toml` files override the globals), Bun via Homebrew, Python via uv.
- **Editor.** Neovim with the config from `https://github.com/rena0157/lazy.nvim` on a blank machine. An existing `~/.config/nvim` is never touched. Set `NVIM_CONFIG_REPO=none` for stock Neovim.
- **Git.** Sensible defaults filled only when absent (delta pager, zdiff3, rebase on pull, autoSetupRemote, rerere, histogram diff), `gh` as the GitHub credential helper, and a global ignore at `~/.config/git/ignore`.
- **System tuning (full profile).** `etc/sysctl.d/90-dev.conf` raises inotify watches and mmap limits for file watchers; `etc/security/limits.d` and systemd drop-ins raise the open-file ceiling; Docker gets log rotation, BuildKit, and a private address pool; the timezone is set; `fstrim.timer` and unattended security upgrades are enabled.
- **Maintenance timers (full profile).** User-level systemd timers, enabled with lingering so they run while you are logged out: `brew-upgrade` weekly, `docker-prune` weekly (never touches named volumes), and `backup` nightly when restic is configured.
- **Backups.** `backup/backup.sh` snapshots `~/src`, `~/.config`, `~/.ssh`, agent settings, and the installed system files to any restic repository, keeps 7 daily / 4 weekly / 6 monthly, and verifies a rotating slice of the repo. Configure it by copying `backup/restic-env.example` to `~/.config/restic/env` (mode 0600) and rerunning setup. Check with `systemctl --user list-timers` and `journalctl --user -u backup`.
- **Tailscale.** Installed and enabled; `tailscale up` remains a manual, authenticated step. mosh only works over the tailnet IP because exe.dev's SSH is proxied.

## Configuration and safety

The repository symlinks `zshrc`, `zprofile`, `zsh/p10k.zsh`, `zellij/config.kdl`, and `git/ignore` into the home directory. A different existing file is moved to a timestamped backup first; a correct symlink is left alone. Machine-local secrets live in `~/.config/shell/env` (mode 0600, enforced by `doctor.sh`); non-secret local overrides go in `~/.zshrc.local`. Re-running setup is safe: package managers converge state, system files are compared before being rewritten, services and group membership are checked, and SSH keys are only created when absent.

The repository contains no credentials. Do not add tokens, private keys, `.env` files, restic passwords, or backup destinations.

## Authentication checklist

Run setup as a regular user with sudo access, not as root. After the first run:

1. `gh auth login` (git then authenticates through gh automatically).
2. `sudo tailscale up --ssh`, then disable key expiry for the node in the Tailscale admin console.
3. `atuin login` (or `atuin register`) if you want history synced across machines.
4. Copy `backup/restic-env.example` to `~/.config/restic/env`, `chmod 600` it, write the repo password to `~/.config/restic/password`, and rerun `./setup.sh` to enable the nightly timer.
5. Log out/in once so the `docker` group applies; validate with `docker run --rm hello-world`.
6. Authenticate optional AI CLIs individually. Never store their tokens in this repository.

On the Mac side, add the VM to `~/.ssh/config` with its tailnet name so `mosh <name>` works, and keep the exe.dev HTTPS proxy private: `https://<name>.exe.xyz` serves port 8000 and ports 3000-9999 are forwarded behind exe.dev login.

## Validation and development

```bash
./setup.sh --check                 # actionable host diagnostics
./scripts/doctor.sh --profile core
./tests/test.sh                    # pure behavior/manifest checks
shellcheck setup.sh bootstrap.sh exe-new.sh scripts/doctor.sh backup/backup.sh tests/test.sh
```

CI runs syntax checks, ShellCheck, the tests, Brewfile syntax validation, and systemd unit verification on Ubuntu 24.04. It uses `--dry-run` rather than mutating the CI host.
