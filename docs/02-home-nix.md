# 02 - `home.nix`

This file is the whole environment. On macOS the video splits its config between
`configuration.nix` (system level, via nix-darwin) and `home.nix` (user level).
Here there is no system level, so everything lands in one file.

## Header

```nix
{ config, pkgs, user, ... }:
```

Module arguments. `config` is the evaluated configuration (used below to read
`home.homeDirectory` and to reach `config.lib.file.mkOutOfStoreSymlink`), `pkgs`
is the package set from `flake.nix`, and `user` arrives via `extraSpecialArgs`.

```nix
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
```

The stable path every symlink is written against. Note it points at
`~/.dotfiles`, **not** at wherever you happened to clone the repo. Both
`bootstrap.sh` and `rebuild.sh` create that symlink before doing anything else.
This is the same trick the video uses at 02:53: it means you can move or rename
the clone and nothing breaks.

```nix
  herdr = pkgs.callPackage ./modules/herdr.nix { };
in
```

`callPackage` reads the function in `modules/herdr.nix` and automatically
supplies the arguments it asks for (`lib`, `stdenvNoCC`, `fetchurl`) from
`pkgs`. Explained in [03-modules-herdr-nix.md](03-modules-herdr-nix.md).

## Identity

```nix
  home.username = user;
  home.homeDirectory = "/home/${user}";
  home.stateVersion = "26.05";
```

`homeDirectory` is `/home/<user>` on Linux, where macOS uses `/Users/<user>`.
Getting this wrong makes every symlink land in the wrong place.

`stateVersion` pins default values that home-manager may change in future
releases, so an upgrade cannot silently alter behavior you depend on. Set it
once, to the release you first installed with, then never touch it. It is not a
version to keep current.

## Packages

```nix
  home.packages = with pkgs; [
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line, also used by the claude status line
    lazygit
    neovim
    git
    herdr
    nerd-fonts.hack
  ];
```

`with pkgs;` lets you write `ripgrep` instead of `pkgs.ripgrep`.

Everything the video installs through Homebrew that still runs inside Linux is
here instead, with one deliberate exception: `claude-code`. It ships a
self-updater, and a read-only Nix store is the wrong home for anything that
updates itself - see [08-agents.md](08-agents.md).

`jq` earns its place independently: `scripts/sync-windows-terminal.sh` uses it
to merge into the Windows Terminal settings file.

`git` is listed even though `bootstrap.sh` requires git to clone the repo. That
bootstrap git comes from apt; this one is Nix-managed and pinned, and takes
precedence on `PATH` after the first switch.

Search for more at [search.nixos.org](https://search.nixos.org/packages).

```nix
  fonts.fontconfig.enable = true;
```

Registers Nix-installed fonts with Linux fontconfig. That covers Linux GUI apps
under WSLg, but **not** the terminal you actually look at, which is a Windows
process reading the Windows font store.

`nerd-fonts.hack` is nonetheless in `home.packages`, and it is the single source
for both sides: `scripts/sync-windows-terminal.sh` copies these exact files out
of the Nix store into the Windows font directory. So the font version is pinned
by `flake.lock` like everything else, rather than by a download URL. See
[09-windows-bridge.md](09-windows-bridge.md).

## Environment

```nix
  home.sessionVariables = {
    EDITOR = "nvim";
  };
```

`EDITOR` is straight from the video.

`sessionVariables` are exported by the session init script, so a shell started
before a rebuild will not see changes. Open a new shell.

## zsh

```nix
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
```

`programs.zsh.enable` does more than install zsh: it generates `~/.zshrc` and
wires in the plugins. Do not hand-edit `~/.zshrc`; it is overwritten on every
switch. Put shell code in `initContent` instead.

```nix
    initContent = ''
      bindkey '^f' autosuggest-accept
```

Pasted verbatim into the generated `.zshrc`. `ctrl+f` accepts the ghost-text
suggestion, exactly as in the video at 14:12.

```nix
      case "$PWD" in
        /mnt/*) cd "$HOME" ;;
      esac
```

WSL-specific. Launching WSL from certain Windows entry points drops you in
`/mnt/c/Users/<you>`, which is the Windows filesystem exposed over a 9p mount.
File operations there are roughly an order of magnitude slower and Unix
permissions do not survive. Bouncing to `$HOME` avoids accidentally starting
work on the slow side.

```nix
      winhome() {
        cd "$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d "\r")")"
      }
    '';
```

Jumps to your Windows user profile. It asks Windows for `%USERPROFILE%` rather
than assuming `/mnt/c/Users/<same-name>`, because your Windows and WSL usernames
are frequently different. `wslpath` converts `C:\Users\x` into `/mnt/c/Users/x`,
and `tr -d "\r"` strips the CR that Windows appends.

```nix
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
      e = "explorer.exe .";
    };
  };
```

Straight from the video, plus `e`. Note WSL puts Windows executables on `PATH`,
so `explorer.exe .` opens the current Linux directory in Windows Explorer
through the `\\wsl.localhost` bridge.

`cc` and `co` disable the agents' permission prompts. That is what the video
does, but understand the tradeoff before using them outside a sandbox.

## Starship

```nix
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
```

`settings` is translated by home-manager into `~/.config/starship.toml`, so you
get the whole Starship config surface without leaving Nix.

`format` lists the prompt segments in order: directory, git branch, git status,
how long the last command took, a line break, then the prompt character. The
character turns red when the previous command failed, which is the cheapest
error signal you can have. Unlisted modules are simply not rendered, which is
also what keeps the prompt fast.

The `❯` glyph and any git symbols need a Nerd Font in the terminal, which is why
the font install is not optional.

## The symlinks

```nix
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
```

This is the most important mechanism in the repo, and it is worth being precise
about what it does.

Ordinary `home.file` copies content into the Nix store and symlinks to it. Store
paths are **read-only**, so a program that rewrites its own config at runtime
would fail, and you would have to rebuild after every edit.

`mkOutOfStoreSymlink` instead creates a symlink pointing at a path *outside* the
store - here, straight into this git repo. So:

- Editing `home/.config/nvim/lua/keys.lua` takes effect immediately. No rebuild.
- Anything Neovim writes back into its config directory shows up as a change in
  `git status`, which is how the setup stays version-controlled.

The tradeoff: the link target is resolved at *activation* time and not checked
for existence. If `~/.dotfiles` does not exist yet, you get a dangling symlink
rather than a build error. That is exactly why both scripts run
`ln -sfn "$DIR" ~/.dotfiles` before switching.

```nix
  home.file.".config/herdr".source = ... ;
```

Same mechanism.

Note what is **not** here: `~/.claude/`. Claude Code rewrites its own
`settings.json` as you change themes and models, and `CLAUDE.md` is edited by
hand. Pointing home-manager at either one replaces whatever you already had with
a store symlink. Only symlink files this repo is the sole author of.

```nix
  # No terminal-emulator config is symlinked here.
```

The deliberate omission. The terminal is a Windows process and cannot read Linux
dotfiles at all, so a symlink would achieve nothing. Its settings live in
`home/windows-terminal/` and are pushed across the boundary by the sync script
instead. See [05-terminal.md](05-terminal.md).

```nix
  home.file.".codex/AGENTS.md".source = ... "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source = ... same target ...;
```

One file, several link targets. Each agent looks for its memory file in a
different place and under a different name, so this fans a single source out to
all of them. Edit `home/AGENTS.md` and every agent picks it up at once, with no
rebuild. This is the video's 39:36 chapter.

Claude Code is the exception: it reads `~/.claude/CLAUDE.md`, which is left
unmanaged for the reason above. Copy the parts you want, or symlink it yourself
if the file is not already in use.

```nix
  programs.home-manager.enable = true;
```

Puts the `home-manager` command itself into your profile. Without it,
`rebuild.sh` would have no binary to call and you would be stuck using
`nix run home-manager -- ...` forever.

## Adding to this file

```nix
# a package
home.packages = with pkgs; [ ... bat ];

# an alias
programs.zsh.shellAliases.gs = "git status";

# another config directory linked from the repo
home.file.".config/foo".source =
  config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/foo";
```

Then `./rebuild.sh`.
