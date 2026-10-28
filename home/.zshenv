# Read by every zsh, interactive or not, so keep it to environment only.

export EDITOR="nvim"

# Ubuntu's /etc/zsh/zshrc runs compinit unless this is set; ~/.zshrc already
# does, and running it twice only slows every new shell down.
skip_global_compinit=1

# Everything this repo installs outside apt lands in ~/.local/bin: uv and the
# tools it installs, npm globals (prefix ~/.local, set by bootstrap.sh), herdr,
# lua-language-server, Claude Code, the AWS CLI. Ahead of /usr/bin on purpose,
# so a newer copy installed here wins over an older apt one.
typeset -U path
path=( "$HOME/.local/bin" $path )

# rustup's env file. bash gets it from ~/.profile; a zsh login shell reads
# neither .profile nor .bashrc, so it needs its own copy of the line.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
