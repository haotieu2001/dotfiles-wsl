{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # herdr is not in nixpkgs, so we package the upstream static binary
  # ourselves, pinned by version + hash. See modules/herdr.nix.
  herdr = pkgs.callPackage ./modules/herdr.nix { };

  # CPU/RAM readout pinned to the terminal's top row. See modules/statusbar.nix.
  statusbar = pkgs.callPackage ./modules/statusbar.nix { };
in

{
  home.username = user;
  home.homeDirectory = "/home/${user}";   # macOS uses /Users/<name>
  home.stateVersion = "26.05";

  # On macOS this list lived partly in nixpkgs and partly in Homebrew casks.
  # On WSL there is no Homebrew: everything that runs inside Linux comes from
  # nixpkgs. The one thing that must render on the Windows side is the font,
  # which is still sourced from here and pushed across the boundary by
  # scripts/install-windows-font.sh.
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    git
    gh        # github cli: PRs, releases, and the thing that holds the API token
    tree
    herdr       # agent multiplexer
    statusbar   # CPU/RAM readout pinned to the terminal's top row

    # Language toolchains that used to be installed by hand: node came from
    # nvm, uv from a curl'd binary in ~/.local/bin. Neither survived a new
    # machine, which defeated the point of the repo. These are the versions
    # that should exist on *every* machine; per-project versions belong in
    # that project's own flake instead. See docs/README.md.
    nodejs_24
    uv

    # Language servers for Neovim, so `gd` and diagnostics actually work.
    #
    # From nixpkgs rather than mason on purpose. mason fetches its own binaries
    # into ~/.local/share/nvim: not in flake.lock, not on the next machine, and
    # exactly the drift scripts/check-drift.sh reports. A language server is a
    # tool like any other, so it is pinned like any other.
    lua-language-server          # this config
    nil                          # nix files: home.nix, flake.nix
    basedpyright                 # python
    typescript-language-server   # javascript, typescript
    bash-language-server         # bootstrap.sh and scripts/

    # direnv is deliberately NOT listed here. The programs.direnv block further
    # down already installs it; listing it again is a second, redundant path to
    # the same package.

    # claude-code is deliberately NOT here. It ships a self-updater that keeps
    # itself current in ~/.local/bin; pinning it in the Nix store freezes it at
    # whatever flake.lock says and shadows the newer copy on PATH. Tools that
    # update themselves are a bad fit for a read-only store.

    # The terminal font. Pinned here by flake.lock, then copied across the
    # WSL/Windows boundary by scripts/install-windows-font.sh, because the
    # Windows font renderer cannot see Linux fontconfig.
    nerd-fonts.hack
  ];

  # Registers the font with Linux fontconfig. The Windows terminal that
  # actually draws your glyphs cannot see this, so the same Nix-store font
  # files are copied to the Windows font directory by the install script.
  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Tools that install themselves into ~/.local/bin need that directory on
  # PATH, and nothing else puts it there for a zsh login shell. Ubuntu adds it
  # from ~/.profile, which bash reads and zsh does not.
  #
  # This matters because the package list above deliberately leaves claude-code
  # out: it self-updates, and the Nix store is read-only. Without this line the
  # config says "claude lives in ~/.local/bin" and then hands you a shell that
  # cannot find it. Same for anything installed by `pip install --user`.
  #
  # Ordering is the point. home-manager writes this into ~/.zshenv, which zsh
  # reads *before* ~/.zprofile, and .zprofile is where the Nix profile goes on
  # PATH. So the Nix copy still wins for anything home.nix declares, and
  # ~/.local/bin only answers for what Nix does not manage. Reversing that
  # order is exactly the drift scripts/check-drift.sh reports.
  #
  # That only holds because programs.zsh.profileExtra below re-prepends the Nix
  # profile explicitly. Relying on .zprofile's `. nix.sh` alone is not enough:
  # it self-guards and no-ops when a login bash already sourced it, which is
  # what happens on every machine where chsh fails. See the comment there.
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid

    # Put Nix on PATH for login shells. This writes ~/.zprofile.
    #
    # The Nix installer drops its setup script in /etc/profile.d/nix.sh, which
    # only shells that read /etc/profile ever see. bash does. zsh does not,
    # unless the distro ships /etc/zsh/zprofile to forward it, and Ubuntu only
    # ships that with its own zsh package - which we do not install, because
    # zsh comes from Nix here.
    #
    # So on a machine where step 6 of bootstrap.sh succeeds and zsh really
    # becomes the login shell, that shell starts with no Nix on PATH at all:
    # no nvim, no git, no herdr, not even nix itself. It only ever appeared to
    # work on machines where `chsh` failed, because the ~/.bashrc fallback runs
    # /etc/profile first and the `exec zsh` inherits an already-correct PATH.
    #
    # Found by installing on a clean WSL instance. It cannot be reproduced on a
    # machine that is already set up, which is the entire argument for testing
    # against a fresh one.
    profileExtra = ''
      if [ -e /etc/profile.d/nix.sh ]; then
        . /etc/profile.d/nix.sh
      elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi

      # nix-daemon.sh guards itself with __ETC_PROFILE_NIX_SOURCED and returns
      # immediately if that is already set. So the block above is a no-op in
      # exactly one situation: chsh failed, bootstrap.sh installed the
      # ~/.bashrc fallback, and a login bash sourced Nix and then `exec zsh -l`.
      # The guard is exported, so zsh inherits it.
      #
      # By that point ~/.zshenv has already run and prepended ~/.local/bin from
      # home.sessionPath. With nothing putting the Nix profile back in front,
      # ~/.local/bin ends up first and shadows every tool this config declares.
      # That is precisely the inversion scripts/check-drift.sh reports.
      #
      # Found on a clean WSL instance where chsh failed. It cannot be
      # reproduced on a machine where zsh is already the login shell, because
      # there no bash ever sources Nix first - the same blind spot as the
      # profileExtra bug above it.
      typeset -U path
      path=( "$HOME/.nix-profile/bin" /nix/var/nix/profiles/default/bin $path )
    '';

    initContent = ''
      bindkey '^f' autosuggest-accept

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

      # Pin CPU/RAM to the terminal's top row. See modules/statusbar.nix for
      # why this is a raw scroll-region trick rather than a tmux status line:
      # this repo doesn't manage tmux, and herdr, the multiplexer actually in
      # use, has no status-bar concept of its own.
      #
      # STATUSBAR_PID is exported, so a nested shell (a script, or `zsh` run
      # by hand) inherits it and skips relaunching rather than stacking a
      # second bar on the same terminal. `disown` only silences the "you have
      # running jobs" warning on exit - it does not stop the terminal from
      # sending SIGHUP when the pty itself closes, which is what actually
      # triggers the trap in modules/statusbar.nix that restores the
      # scroll region.
      if [[ -o interactive ]] && [[ -t 1 ]] && [[ -z "''${STATUSBAR_PID:-}" ]]; then
        statusbar &
        export STATUSBAR_PID=$!
        disown
      fi
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
      # WSL-only convenience: open the current directory in Windows Explorer
      e = "explorer.exe .";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Per-project toolchains. `cd` into a directory with a flake.nix and an
  # .envrc, and that project's compiler, runtime and tools appear on PATH; `cd`
  # out and they are gone. This is what replaces nvm, pyenv, and installing
  # things globally with `pip --user`.
  #
  # nix-direnv makes it usable day to day: plain direnv re-evaluates the whole
  # flake on every `cd`, which takes seconds, and keeps no GC root so your
  # toolchain gets garbage-collected out from under you. nix-direnv caches the
  # result and pins it. See docs/README.md.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";

  # ~/.claude is deliberately NOT managed here. Claude Code's settings.json and
  # CLAUDE.md are edited in place by the tool and by hand, and home-manager
  # replacing them with store symlinks silently displaces whatever was already
  # there. Only symlink files this repo is the sole author of.

  # No terminal config is managed here either. The terminal is a Windows
  # process that cannot read Linux dotfiles, and its settings.json is edited
  # through its own UI - every value in it is a matter of taste. Only the font
  # crosses the boundary. See docs/README.md.

  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  programs.home-manager.enable = true;
}
