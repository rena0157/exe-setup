# exe-setup

A one-command, idempotent bootstrap for an Ubuntu development machine. `setup.sh` is the orchestrator; `bootstrap.sh` only installs Git, obtains this repository, and hands off to it. Homebrew's `Brewfile` is the source of truth for global CLI tools, while `apt-packages.txt` contains host packages. **Hermes is explicitly excluded.** Machine-specific rclone configuration and backups are also excluded.

## Run it

Review the repository, then clone and run:

```bash
git clone https://github.com/rena0157/exe-setup.git ~/.local/share/exe-setup
cd ~/.local/share/exe-setup
./setup.sh
```

On a blank Ubuntu host, the small bootstrap can clone and run everything:

```bash
curl -fsSL https://raw.githubusercontent.com/rena0157/exe-setup/main/bootstrap.sh | bash
```

Arguments can be passed through stdin scripts, for example:

```bash
curl -fsSL https://raw.githubusercontent.com/rena0157/exe-setup/main/bootstrap.sh \
  | bash -s -- --profile core --no-shell-change
```

**Security:** `curl | bash` executes mutable remote code without review. Prefer cloning and inspecting it. For automation, download the script, verify it, and set `EXE_SETUP_REF` to a reviewed commit SHA. The bootstrap repository URL/destination can be changed with `EXE_SETUP_REPO` and `EXE_SETUP_DIR`.

## Options

```text
--profile full|core  core skips configuration of Docker/Tailscale and SSH key creation
--with-ai            opt in to pi, Claude Code, and Codex (never Hermes)
--no-shell-change    leave the current login shell unchanged
--dry-run            print actions without changing the machine
--check              run the read-only doctor
--help               show command help
```

`full` is the default. The Ubuntu package manifest includes Docker and Mosh for a consistent host baseline; the core profile does not enable Docker, install Tailscale, alter Docker group membership, or generate an SSH key. Runtime and optional AI package versions can be overridden with `MISE_NODE_VERSION`, `MISE_GO_VERSION`, and `PI_NPM_PACKAGE`.

## Installed architecture

- Ubuntu packages from `apt-packages.txt`: build prerequisites, Git, Docker Engine with Compose/Buildx, Mosh, SSH client, and utilities.
- Global CLI packages from `Brewfile`: zsh, GitHub CLI, Neovim, Zellij, Bun, mise, uv, ripgrep, fd, eza, fzf, bat, zoxide, delta, jq/yq, and diagnostics/formatters.
- Node 24 and Go 1.26 are managed by **mise** by default. Override them with `MISE_NODE_VERSION` and `MISE_GO_VERSION`; project-local mise files take precedence.
- **uv** supplies Python and is the recommended interface for Python versions, virtual environments, tools, and dependencies.
- Tailscale uses its official Ubuntu installer because it is a system service. Docker uses Ubuntu's `docker.io` package.
- Oh My Zsh is installed without invoking its interactive installer.
- AI coding CLIs are opt-in with `--with-ai`: the configured pi package and Codex use npm; Claude uses its official installer. `PI_NPM_PACKAGE` defaults to `@earendil-works/pi-coding-agent` and can be overridden.

## Configuration and safety

The repository symlinks `zshrc`, `zprofile`, and `zellij/config.kdl` into the home directory. A different existing file is moved to a timestamped backup first; a correct symlink is left alone. Both login and interactive shells initialize Homebrew and user paths, and mise is activated in interactive zsh.

Neovim itself is installed, but an existing `~/.config/nvim` is never touched. A blank machine clones `https://github.com/rena0157/lazy.nvim.git` by default. Override `NVIM_CONFIG_REPO` with another public, secret-free Git URL, or set it to `none` to use clean Neovim defaults.

Git's safe defaults are filled only when absent. Existing `user.name` and `user.email` are preserved. Identity fields are changed only when explicitly supplied:

```bash
GIT_NAME='Ada Lovelace' GIT_EMAIL='ada@example.com' ./setup.sh
```

The repository contains no credentials. Do not add tokens, private keys, `.env` files, rclone remotes, or backup destinations. Machine-local environment variables may live in `~/.config/shell/env`; the managed zsh configuration sources it when present, and `doctor.sh` enforces mode `0600`. Re-running setup is safe: package managers converge state, existing configs are detected, services and group membership are checked, and SSH keys are only created when absent.

## Authentication checklist

Run setup as a regular user with passwordless or interactive `sudo` access, not as root. Setup deliberately does not automate account credentials. After installation:

1. Review the generated/existing public key and add it to GitHub; run `gh auth login`.
2. Run `tailscale up` for the intended tailnet (full profile).
3. Log out/in if setup added you to the `docker` group; validate with `docker run --rm hello-world`.
4. Authenticate optional AI CLIs individually. Never store their tokens in this repository.
5. Configure project secrets in an appropriate secret manager.

## Validation and development

```bash
./setup.sh --check                 # actionable host diagnostics
./scripts/doctor.sh --profile core
./tests/test.sh                    # pure behavior/manifest checks
bash -n setup.sh bootstrap.sh scripts/doctor.sh tests/test.sh
shellcheck setup.sh bootstrap.sh scripts/doctor.sh tests/test.sh
```

CI runs syntax checks, ShellCheck, tests, and manifest syntax validation on Ubuntu 24.04. It intentionally uses `--dry-run` rather than mutating the CI host.
