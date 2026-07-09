# zsh config for jailed-shell. Committed and self-contained: it depends only on
# zsh and git (both present in the jail), with no /nix/store paths, so it stays
# valid across GC and nixpkgs bumps. It is bound read-only into the jail from
# agentshome/.config/zsh; history and the completion cache live in the jail's
# tmpfs $HOME, so nothing persists outside the sandbox. Edit freely.

# Completion — dump to the tmpfs $HOME (this config dir is read-only in the jail).
ZSH_CACHE="$HOME/.cache/zsh"
mkdir -p "$ZSH_CACHE"
autoload -Uz compinit && compinit -d "$ZSH_CACHE/zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Git branch in the prompt.
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats ' %F{magenta}(%b)%f'
setopt PROMPT_SUBST
precmd() { vcs_info }

# Two-line prompt: yellow "user@jail" flags the sandbox, blue cwd, magenta git
# branch, and a caret that turns red after a non-zero exit.
PROMPT='%F{green}%n@jail%f %F{blue}%~%f${vcs_info_msg_0_}
%F{%(?.green.red)}❯%f '

# History in the tmpfs $HOME (ephemeral).
HISTFILE="$ZSH_CACHE/history"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# A few conveniences.
alias l='ls -alh'
alias ll='ls -lh'
alias la='ls -A'
