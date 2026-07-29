{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # herdr is not in nixpkgs, so we package the upstream static binary
  # ourselves, pinned by version + hash. See modules/herdr.nix.
  herdr = pkgs.callPackage ./modules/herdr.nix { };
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

    herdr     # agent multiplexer

    # Language toolchains that used to be installed by hand: node came from
    # nvm, uv from a curl'd binary in ~/.local/bin. Neither survived a new
    # machine, which defeated the point of the repo. These are the versions
    # that should exist on *every* machine; per-project versions belong in
    # that project's own flake instead. See docs/11-devshells.md.
    nodejs_24
    uv

    # Loads a project's devShell on `cd` and unloads it on the way out.
    # Pointless without the programs.direnv block further down, which is what
    # actually hooks it into zsh.
    direnv

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

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
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
  # result and pins it. See docs/11-devshells.md.
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
  # crosses the boundary. See docs/05-terminal.md.

  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  programs.home-manager.enable = true;
}
