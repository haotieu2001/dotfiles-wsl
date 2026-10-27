# Interactive zsh. Linked to ~/.zshrc by bootstrap.sh; edits apply to the next shell.

autoload -U compinit && compinit

# History: the same settings home-manager used to generate.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_FCNTL_LOCK HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# Plugins from apt (zsh-autosuggestions, zsh-syntax-highlighting).
if [ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_STRATEGY=(history)
  bindkey '^f' autosuggest-accept
fi

# WSL starts you in /mnt/c/... when launched from some Windows entry
# points. Anything under /mnt is a slow 9p mount, so bounce to $HOME.
case "$PWD" in
  /mnt/*) cd "$HOME" ;;
esac

# Jump to the Windows user profile without hardcoding the Windows
# username, which often differs from the WSL one.
winhome() {
  cd "$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d "\r")")"
}

# Hand a file to whatever Windows app owns its extension - in practice
# an .html report landing in the default browser. The Linux reflex here
# is xdg-open, which cannot work: there is no desktop session behind it
# in WSL, so it errors or launches a Linux browser that is not installed.
#
# explorer.exe is the working equivalent, but it only understands Windows
# paths, hence wslpath. Passing it a bare Linux path silently opens the
# wrong thing or nothing at all.
#
# The existence check is not decoration: given a path that does not
# exist, explorer.exe still exits 0 and either does nothing or pops a
# Windows error dialog, so a typo looks exactly like success from here.
#
# The explicit `return 0` is the other half of that. explorer.exe exits
# 1 even when it worked, which would paint the starship prompt red after
# every call and make each success look like a failure.
open() {
  if [ $# -eq 0 ]; then
    print -u2 "usage: open <file>"
    return 2
  fi
  if [ ! -e "$1" ]; then
    print -u2 "open: no such file or directory: $1"
    return 1
  fi
  explorer.exe "$(wslpath -w "$1")" >/dev/null 2>&1
  return 0
}

if [[ $TERM != "dumb" ]] && command -v starship >/dev/null; then
  eval "$(starship init zsh)"
fi

# direnv still loads a project's .envrc (environment variables, a .venv).
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

alias ..='cd ..'
alias add='git add .'
alias push='git push'
alias pull='git pull'
alias m='git switch main'
alias cc='claude --dangerously-skip-permissions'
alias co='codex --full-auto'
# WSL-only convenience: open the current directory in Windows Explorer
alias e='explorer.exe .'

# Debian names fd's binary fdfind; bootstrap.sh links ~/.local/bin/fd to it.

# Syntax highlighting must be sourced last: it wraps every widget defined before it.
if [ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)
fi
