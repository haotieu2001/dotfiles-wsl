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
  # nixpkgs. Things that must render on the Windows side (WezTerm, the font)
  # are installed by windows/setup-windows.ps1 instead.
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line, also used by the claude status line
    lazygit
    neovim
    git

    herdr       # agent multiplexer (was `brews = [ "herdr" ]` on macOS)
    claude-code # was `casks = [ "claude-code" ]` on macOS
  ];

  # Installs the font into the *Linux* fontconfig tree. That covers Linux GUI
  # apps under WSLg. It does NOT reach a WezTerm running as a Windows app,
  # which is why setup-windows.ps1 installs Hack Nerd Font on Windows too.
  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    # Claude Code ships its own updater, which cannot write into the read-only
    # Nix store. Turn it off and let `nix flake update` handle versioning.
    DISABLE_AUTOUPDATER = "1";
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

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  # The WezTerm config still lives in this repo, but it is consumed from the
  # Windows side over \\wsl.localhost, so there is no ~/.config/wezterm symlink
  # here. windows/setup-windows.ps1 writes the loader stub. See docs/04-wezterm.md.

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  programs.home-manager.enable = true;
}
