# 02 - `home.nix`

This one file holds the whole setup. A NixOS or nix-darwin machine splits its
settings between `configuration.nix` for the system and `home.nix` for the user.
Here there is no system part, so everything is in one place.

## The top of the file

```nix
{ config, pkgs, user, ... }:
```

Three things get passed in. `config` is the finished setup, which we read later
to find your home folder. `pkgs` is the package set from `flake.nix`. `user` is
your username, sent down by `extraSpecialArgs`.

```nix
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
```

The path that every file link points at. Note it points at `~/.dotfiles`, **not**
at wherever you cloned the repo. Both `bootstrap.sh` and `rebuild.sh` create that
link before anything else. This way you can move or rename the folder and nothing
breaks.

```nix
  herdr = pkgs.callPackage ./modules/herdr.nix { };
in
```

`callPackage` reads the file `modules/herdr.nix` and fills in the arguments it
asks for (`lib`, `stdenvNoCC`, `fetchurl`) from `pkgs`. See
[03-modules-herdr-nix.md](03-modules-herdr-nix.md).

## Who you are

```nix
  home.username = user;
  home.homeDirectory = "/home/${user}";
  home.stateVersion = "26.05";
```

On Linux your home folder is `/home/<name>`. On macOS it would be
`/Users/<name>`. Get this wrong and every file link lands in the wrong place.

`stateVersion` locks in default values that home-manager might change in a
future release. It stops an upgrade from quietly changing how things behave.
Set it once, to the release you first installed, and never touch it again. It is
**not** a version number to keep up to date.

## Packages

```nix
  home.packages = with pkgs; [
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # read json on the command line
    lazygit
    neovim
    git
    gh
    herdr
    nodejs_24
    uv
    nerd-fonts.hack
  ];
```

`with pkgs;` lets you write `ripgrep` instead of `pkgs.ripgrep`.

**What belongs in this list:** tools you want on *every* computer you own.

**What does not:** a version of Python or Node that only one project needs.
Those go in that project's own flake, so the version travels with the code
instead of living on one laptop. See [11-devshells.md](11-devshells.md).

`nodejs_24` and `uv` are the general ones, for when you run `npx` or
`uv tool install` outside any project. Before, Node came from nvm and uv was a
file downloaded by hand into `~/.local/bin`. Neither survived a new computer.

`direnv` is **not** in this list, even though you get it. The `programs.direnv`
block further down installs it *and* connects it to zsh, so naming it here as
well would be a second, redundant path to the same package. The rule: if a
`programs.*` block already enables a tool, do not also list it in
`home.packages`.

`gh` fills a gap that an SSH key cannot. An SSH key only proves who you are for
git itself: clone, fetch, push. Pull requests are not git. Making and merging
them goes through GitHub's web API, which does not accept SSH keys at all.
`gh auth login` gets a token and saves it in `~/.config/gh/hosts.yml`.

Leave the token there. Do not put `export GH_TOKEN=...` in your shell settings.
An exported token can be read by every program you start, including AI tools.
The `gh` file cannot.

`jq` is here because it is the normal way to read JSON on the command line, and
because `apply-windows-terminal-theme.sh` uses it to merge your terminal
colours.

One thing is left out on purpose: `claude-code`. It updates itself, and the Nix
store is read-only, so the two do not mix. See [08-agents.md](08-agents.md).

`git` is in the list even though you need git to clone this repo. That first git
comes from apt. This one comes from Nix, is locked to a version, and wins once
you have installed.

Search for more packages at [search.nixos.org](https://search.nixos.org/packages).

```nix
  fonts.fontconfig.enable = true;
```

Tells Linux about fonts that Nix installed. That covers Linux windows under
WSLg, but **not** the terminal you actually look at. That one is a Windows
program reading the Windows font list.

`nerd-fonts.hack` is still in the list above, and it is the single source for
both sides. `scripts/install-windows-font.sh` copies those exact files into the
Windows font folder. So the font version is locked by `flake.lock` like
everything else. See [09-windows-bridge.md](09-windows-bridge.md).

## Environment

```nix
  home.sessionVariables = {
    EDITOR = "nvim";
  };
```

These are set when your shell starts. A shell you opened *before* a rebuild will
not see the change. Open a new one.

## zsh

```nix
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # grey text from your history
    syntaxHighlighting.enable = true;  # commands turn green when valid
```

`programs.zsh.enable` does more than install zsh. It writes your `~/.zshrc` and
sets up the plugins. Do not edit `~/.zshrc` by hand; it is overwritten on every
rebuild. Put your own shell code in `initContent` instead.

```nix
    initContent = ''
      bindkey '^f' autosuggest-accept
```

This text is copied straight into the generated `.zshrc`. `ctrl+f` accepts the
grey suggested text.

```nix
      case "$PWD" in
        /mnt/*) cd "$HOME" ;;
      esac
```

Only needed on WSL. Some ways of starting WSL drop you in
`/mnt/c/Users/<you>`, which is the Windows disk seen from Linux. Files there are
roughly ten times slower, and Linux file permissions do not work. This jumps you
back to your home folder so you do not start working on the slow side by
accident.

```nix
      winhome() {
        cd "$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d "\r")")"
      }
    '';
```

Jumps to your Windows user folder. It asks Windows where that is, instead of
guessing `/mnt/c/Users/<same-name>`, because your Windows name and your Linux
name are often different. `wslpath` turns `C:\Users\x` into `/mnt/c/Users/x`, and
`tr -d "\r"` removes the extra character Windows adds at the end.

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

WSL puts Windows programs on your `PATH`, so `explorer.exe .` opens the Linux
folder you are in inside Windows Explorer.

`cc` and `co` turn off the permission questions those AI tools normally ask.
Handy, but understand what you are giving up before using them outside a safe
sandbox.

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

home-manager turns `settings` into `~/.config/starship.toml`, so you get all of
Starship's options without leaving Nix.

`format` lists the parts of the prompt in order: folder, git branch, git status,
how long the last command took, a line break, then the prompt symbol. The symbol
turns red when the last command failed, which is the cheapest way to notice a
mistake. Parts you do not list are not drawn, which also keeps the prompt fast.

The `❯` symbol and the git icons need a Nerd Font in your terminal. That is why
installing the font is not optional.

## direnv

```nix
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
```

`enable` installs direnv and, more importantly, adds it to your `.zshrc`. That
hook runs before each prompt and checks whether you walked into or out of a
folder with an `.envrc` file.

`nix-direnv.enable` swaps in a much better version of that check. It matters for
two reasons:

- **Speed.** Plain direnv rebuilds the whole flake every time you walk into the
  folder, which takes seconds. nix-direnv remembers the answer, so only the first
  time is slow.
- **Cleanup.** Plain direnv does not tell Nix that these tools are in use, so
  `nix-collect-garbage` deletes them and the next visit downloads them again.
  nix-direnv marks them as in use, inside the project's `.direnv/` folder.

Together with a project `flake.nix`, this is what makes `cd ~/my-api` put that
project's Python on your `PATH`, and `cd ..` take it away. Full walkthrough in
[11-devshells.md](11-devshells.md).

Nothing happens until a folder has both an `.envrc` file and your permission.
Run `direnv allow` to give it. direnv asks again whenever the file changes, so
nobody can slip code into it behind your back.

## The file links

```nix
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
```

This is the most important trick in the repo, and it is worth being clear about.

Normally `home.file` copies your file into the Nix store and links to the copy.
Store files are **read-only**. So a program that rewrites its own settings would
fail, and you would have to rebuild after every small edit.

`mkOutOfStoreSymlink` makes a link that points *outside* the store, straight into
this git repo. So:

- Editing `home/.config/nvim/lua/keys.lua` works right away. No rebuild.
- Anything Neovim writes back into that folder shows up in `git status`, which is
  how your setup stays saved in git.

The trade-off: the link is made when you rebuild, and nothing checks that the
target exists. If `~/.dotfiles` is missing you get a broken link instead of an
error. That is exactly why both scripts run `ln -sfn "$DIR" ~/.dotfiles` first.

```nix
  home.file.".config/herdr".source = ... ;
```

Same trick.

Notice what is **missing**: `~/.claude/`. Claude Code rewrites its own
`settings.json` when you change themes or models, and you edit `CLAUDE.md` by
hand. Pointing home-manager at either one would replace what you already had.
Only link files this repo alone writes.

```nix
  # No terminal-emulator settings are linked here.
```

Left out on purpose. The terminal is a Windows program and cannot read Linux
files, so a link would do nothing. What crosses over is pushed by scripts
instead: the font on every rebuild, and the colours once when you install. See
[05-terminal.md](05-terminal.md).

```nix
  home.file.".codex/AGENTS.md".source = ... "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source = ... same target ...;
```

One file, several links. Each AI tool looks for its notes in a different place
under a different name, so this points them all at one file. Edit
`home/AGENTS.md` and every tool sees the change at once, with no rebuild.

Claude Code is the exception. It reads `~/.claude/CLAUDE.md`, which we leave
alone for the reason above. Copy the parts you want, or make the link yourself if
that file is not already in use.

```nix
  programs.home-manager.enable = true;
```

Puts the `home-manager` command itself into your profile. Without it,
`rebuild.sh` would have nothing to run, and you would be stuck typing
`nix run home-manager -- ...` forever.

## Adding your own things

```nix
# a package
home.packages = with pkgs; [ ... bat ];

# a shortcut
programs.zsh.shellAliases.gs = "git status";

# another settings folder linked from the repo
home.file.".config/foo".source =
  config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/foo";
```

Then run `./rebuild.sh`.
