# ~/.zshrc — managed by exe-setup

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

export ZSH="$HOME/.oh-my-zsh"
if [ -r "$ZSH/oh-my-zsh.sh" ]; then
  ZSH_THEME="robbyrussell"
  plugins=(git sudo command-not-found)
  zstyle ':omz:update' mode disabled
  source "$ZSH/oh-my-zsh.sh"
fi

# mise manages Node and Go. This activation also exposes global shims.
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

if (( $+commands[fzf] )); then
  source <(fzf --zsh) 2>/dev/null
fi

export EDITOR=nvim
export VISUAL=nvim
export LESS='-FRX'

# Optional machine-local secrets and environment. Keep this file chmod 600.
[ -r "$HOME/.config/shell/env" ] && source "$HOME/.config/shell/env"

alias ls='eza --group-directories-first'
alias ll='eza -lh --group-directories-first --git'
alias la='eza -lah --group-directories-first --git'
alias lt='eza --tree --level=2 --group-directories-first'
alias cat='bat --paging=never'
alias vim='nvim'
alias vi='nvim'
alias g='git'
alias z='zellij'

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd cd)"
fi
