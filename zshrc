# ~/.zshrc — managed by exe-setup

# Powerlevel10k instant prompt. Anything that may prompt for input must go above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ---------- Homebrew and user paths ----------
# Interactive shells are not always login shells, so initialize PATH here too.
if (( $+commands[brew] )); then
  eval "$(brew shellenv)"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# ---------- Terminal / locale ----------
export COLORTERM=truecolor
export TZ="${TZ:-America/Toronto}"

# exe.dev's sshd does not apply PAM limits, so lift the soft open-file limit to the hard ceiling for
# bundlers and test runners. Harmless elsewhere.
if [[ "$(ulimit -Sn)" != unlimited && "$(ulimit -Hn)" != "$(ulimit -Sn)" ]]; then ulimit -Sn "$(ulimit -Hn)" 2>/dev/null; fi

# ---------- systemd user bus (needed for `systemctl --user` over SSH) ----------
if [[ -z "$XDG_RUNTIME_DIR" && -d "/run/user/$UID" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$UID"
fi
if [[ -z "$DBUS_SESSION_BUS_ADDRESS" && -S "$XDG_RUNTIME_DIR/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

# ---------- Oh My Zsh ----------
export ZSH="$HOME/.oh-my-zsh"
if [ -r "$ZSH/oh-my-zsh.sh" ]; then
  ZSH_THEME=""  # prompt is provided by powerlevel10k below
  plugins=(git sudo command-not-found colored-man-pages extract)
  zstyle ':omz:update' mode disabled
  DISABLE_AUTO_TITLE=true
  source "$ZSH/oh-my-zsh.sh"
fi

# ---------- Prompt and shell plugins (installed via Brewfile) ----------
_brew_share="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}/share"
[ -r "$_brew_share/powerlevel10k/powerlevel10k.zsh-theme" ] && source "$_brew_share/powerlevel10k/powerlevel10k.zsh-theme"
[ -r "$_brew_share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$_brew_share/zsh-autosuggestions/zsh-autosuggestions.zsh"
unset _brew_share
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ---------- Runtimes ----------
# mise manages Node, Go, and per-project tool versions (.mise.toml). Bun comes from Homebrew.
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi

# ---------- fzf ----------
if (( $+commands[fzf] )); then
  source <(fzf --zsh) 2>/dev/null
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# ---------- Editor / pager ----------
export EDITOR=nvim
export VISUAL=nvim
export LESS='-FRX'
export BAT_THEME="${BAT_THEME:-Monokai Extended}"

# ---------- exe.dev ----------
# Opt out of the exe.dev LLM gateway environment injection; agents use their own credentials.
export EXE_DEV_DISABLE_GATEWAY=1

# ---------- Machine-local environment and secrets ----------
# Keep ~/.config/shell/env chmod 600. Never commit it. ~/.zshrc.local is for non-secret overrides.
[ -r "$HOME/.config/shell/env" ] && source "$HOME/.config/shell/env"
[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# ---------- Aliases ----------
alias ls='eza --group-directories-first'
alias ll='eza -lh --group-directories-first --git'
alias la='eza -lah --group-directories-first --git'
alias lt='eza --tree --level=2 --group-directories-first'
alias cat='bat --paging=never'
alias vim='nvim'
alias vi='nvim'
alias g='git'
alias lg='lazygit'
alias z='zellij'
alias za='zellij attach -c main'
alias dc='docker compose'
alias doctor='~/.local/share/exe-setup/scripts/doctor.sh'

# ---------- History ----------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS EXTENDED_HISTORY

# atuin: searchable, synced history across machines (run `atuin login` once per machine to sync).
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh)"
fi

# ---------- zoxide (must come after other cd-related hooks) ----------
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd cd)"
fi

# ---------- zsh-syntax-highlighting must be sourced last ----------
_zsh_hl="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[ -r "$_zsh_hl" ] && source "$_zsh_hl"
unset _zsh_hl

# ---------- Auto-attach Zellij on interactive SSH logins ----------
# Opt out for a session with ZELLIJ_AUTO_ATTACH=0, or permanently with: touch ~/.config/shell/no-zellij
if [[ -o interactive && -t 0 && -t 1 && -n "$SSH_CONNECTION" && -z "$ZELLIJ" && "${ZELLIJ_AUTO_ATTACH:-1}" != 0 \
      && ! -f "$HOME/.config/shell/no-zellij" && "$TERM_PROGRAM" != vscode && -z "$CURSOR_TRACE_ID" ]] \
   && (( $+commands[zellij] )); then
  zellij attach -c main
fi
