# ~/.zshrc — managed by exe-setup

# ---------- Homebrew (Linux) ----------
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# ---------- oh-my-zsh ----------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git sudo command-not-found)
zstyle ':omz:update' mode disabled
source "$ZSH/oh-my-zsh.sh"

# ---------- PATH additions ----------
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ]        && export PATH="$HOME/bin:$PATH"

# ---------- fnm (Node) ----------
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# ---------- Bun ----------
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"

# ---------- fzf ----------
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh) 2>/dev/null
fi

# ---------- Editor ----------
export EDITOR="nvim"
export VISUAL="nvim"

# ---------- Aliases ----------
alias ls='eza --group-directories-first'
alias ll='eza -lh --group-directories-first --git'
alias la='eza -lah --group-directories-first --git'
alias lt='eza --tree --level=2 --group-directories-first'
alias cat='bat --paging=never'
alias vim='nvim'
alias vi='nvim'
alias g='git'
alias z='zellij'
alias cc='claude'

# ---------- Less / pager ----------
export LESS='-FRX'

# ---------- History ----------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

# ---------- zoxide (must be last) ----------
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi
