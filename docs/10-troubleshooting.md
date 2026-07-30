# 10 - When things break

Problems you are likely to hit when running this setup on WSL.

## Installing

### `bootstrap.sh` stops and tells me to run `wsl --shutdown`

This is normal. `/etc/wsl.conf` is only read when the distro starts, so turning
on systemd needs a restart. Run this from **PowerShell**, not inside WSL:

```powershell
wsl --shutdown
```

Open Ubuntu again and run `./bootstrap.sh` again. Check it worked with:

```bash
systemctl is-system-running     # "running" or "degraded" are both fine
```

### `nix: command not found` right after installing Nix

The installer only adds Nix to *new* shells. Open a new one, or run:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### `error: experimental Nix feature 'nix-command' is disabled`

Nix was installed some other way than the Determinate installer. Either install
it again with that one, or run:

```bash
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

### `Existing file '/home/you/.bashrc' would be clobbered`

home-manager refuses to overwrite files it did not create. Both scripts already
pass `-b backup`, which renames the old file instead. If you see this, you ran
home-manager yourself without that option. Use `./rebuild.sh`.

### `Could not resolve host` during the first build

```
> trying https://github.com/ogulcancelik/herdr/releases/download/v0.7.5/herdr-linux-x86_64
> curl: (6) Could not resolve host: github.com
error: cannot download herdr-linux-x86_64 from any mirror
```

**This is almost always temporary. Just run `./bootstrap.sh` again.** Nix keeps
what it already downloaded, so the second try carries on instead of starting
over. `bootstrap.sh` also tries three times by itself.

The cause is timing, not a broken setup. WSL sends all network lookups through
Windows, and that path is briefly unavailable while Nix and systemd start up
right after step 2. Most downloads happen before the gap. Files like `herdr` are
downloaded a moment later, inside a sealed build area, and hit it.

The clue is that every retry fails within a few seconds, while other packages in
the same run downloaded fine.

If it keeps happening, check whether name lookups work *inside* the sealed build
area, not just in your shell:

```bash
nix build --impure --no-link --expr '
  (import <nixpkgs> {}).runCommand "dnsprobe" {
    outputHashMode = "flat"; outputHashAlgo = "sha256";
    outputHash = "0000000000000000000000000000000000000000000000000000000000000000";
    nativeBuildInputs = [ (import <nixpkgs> {}).curl ];
  } "cat /etc/resolv.conf 1>&2; curl -sS --connect-timeout 10 -o /dev/null http://cache.nixos.org/ 2>&1; exit 1"
'
```

Read the log it prints. If you see a `nameserver` line and no `curl: (6)`, then
lookups work and the earlier failure was just the timing gap. A truly broken
setup shows an empty or missing `resolv.conf`.

Only if it is really broken, give the build area a fixed name server:

```bash
sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'

[network]
generateResolvConf = false
EOF
sudo rm -f /etc/resolv.conf
printf 'nameserver 10.255.255.254\nnameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf >/dev/null
```

Keep the WSL address first, so a VPN or company network can still find its
internal names. Then run `wsl --shutdown` from PowerShell.

### The first build is very slow

That is expected, once. If it is slow *every* time, check the repo is not on the
Windows disk:

```bash
pwd -P      # should start with /home, not /mnt
```

### `error: attribute 'wsl' missing`

The name does not match. `flake.nix` must define `homeConfigurations."wsl"`, and
the scripts must use `#wsl`.

### `error: Package '<name>' has an unfree license`

You added a program whose licence is not open source. Either
`config.allowUnfree = true` is missing from the `import nixpkgs` block in
`flake.nix`, or nixpkgs was loaded through `legacyPackages`, which ignores that
setting.

## Shell

### Still in bash after installing

Check what step 6 managed to do:

```bash
getent passwd "$USER" | cut -d: -f7
```

If that is not the Nix zsh, set it yourself:

```bash
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
```

`chsh` asks for your **Linux password**, not sudo, and fails on some WSL setups.
Note that `sudo tee` working tells you nothing about whether `chsh` worked. In
the two-command line above, the first half can succeed while the second fails.
Run `chsh` on its own to see the real error.

If it will not work at all, `bootstrap.sh` starts zsh from `~/.bashrc` instead.
To do that by hand, add **this**, not a plain `exec`:

```bash
if shopt -q login_shell && [[ $- == *i* ]] && [ -t 0 ] \
   && [ -z "${ZSH_VERSION:-}" ] && [ -x "$HOME/.nix-profile/bin/zsh" ]; then
  exec "$HOME/.nix-profile/bin/zsh" -l
fi
```

The `shopt -q login_shell` check is the important part. A plain `exec zsh -l` in
`~/.bashrc` also runs for shells that are *not* login shells. So any tool that
runs `bash -ic "some command"` gets zsh started over the top of it, loses the
command, and hangs forever. The `[ -t 0 ]` check keeps it out of pipelines.

Either way, log out and back in. `chsh` does not change the shell you are in
right now.

### `/etc/shells` has zsh listed twice

Harmless, and caused by running the setup twice. Clean it up with:

```bash
sudo cp /etc/shells /etc/shells.bak
sudo awk '!seen[$0]++' /etc/shells.bak | sudo tee /etc/shells >/dev/null
```

### Shortcuts or `$EDITOR` did not change

These are set when a shell starts. Open a new shell.

### The prompt shows boxes instead of symbols

Starship's symbols need a Nerd Font **on Windows**. Run
`./scripts/install-windows-font.sh`, then sign out of Windows and back in.
Programs that are already running often cannot see a newly installed font.

## Terminal

### The font did not change

Run the font script yourself and read what it says:

```bash
./scripts/install-windows-font.sh
```

Then restart Windows Terminal. This script runs on every `./rebuild.sh`, so if
the font is wrong, something it printed will explain why.

### The colours were never applied

Colours are set **once, by `bootstrap.sh` step 8**, not by `rebuild.sh`. Run it
yourself:

```bash
./scripts/apply-windows-terminal-theme.sh
```

Three messages it might print, all on purpose:

- `Windows Terminal settings.json not found` - you have never opened Windows
  Terminal, so it has not written its settings. Open it once, then try again.
- `settings.json is not strict JSON` - your file has comments or extra commas,
  which Windows Terminal allows and this script cannot read. Remove them, or add
  the colours by hand.
- `theme already present; leaving your terminal settings alone` - working as
  designed. Use `--force` if you really want to replace your current colours.

### I changed my terminal and a rebuild undid it

It did not. `rebuild.sh` never writes that file. Only `bootstrap.sh` does, once.
If your colours changed, either someone ran
`apply-windows-terminal-theme.sh --force`, or the change was made in Windows
Terminal's own Settings. See [05-terminal.md](05-terminal.md).

### I want my old terminal settings back

The script saves a copy before its one and only write:

```
<Windows profile>\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\
    settings.json.pre-dotfiles-wsl.<date and time>
```

The merge only adds things anyway. Other colour schemes, your profile list, your
keyboard shortcuts and your actions are never touched. Usually only
`profiles.defaults` and the added colours are different.

### The background picture is missing

The picture is copied to `%LOCALAPPDATA%\dotfiles-wsl\blackpanther.jpg` when the
colours are set. Windows Terminal reads files across the WSL boundary slowly, and
those paths break if you rename your distro, which is why we copy it. If the file
is gone, set it up again:

```bash
./scripts/apply-windows-terminal-theme.sh --force
```

### The background is solid, not see-through

`opacity` must be below 100. We set it to 80. If you changed it later, it is in
Windows Terminal's own Settings. If the terminal is see-through but Neovim is
not, the theme's `transparency` setting is off. See [06-neovim.md](06-neovim.md).

### The terminal opens in `/mnt/c/...`

The zsh rule in `home.nix` jumps you back to your home folder. If it is not
happening, you are probably still in bash. Finish the `chsh` step.

## Tools per project

### `direnv: command not found`

`direnv` is in `home.packages` and connected to zsh by `programs.direnv`. Run
`./rebuild.sh` and open a new shell. The connection is written into your
`.zshrc`, which a shell that is already open has not read.

### Nothing happens when I walk into the project

direnv refuses to run an `.envrc` file until you allow it:

```bash
direnv allow
```

It asks again whenever the file changes. If still nothing happens, check the
folder really has both `.envrc` and `flake.nix`.

### Walking into the folder is slow every time

`nix-direnv.enable` is what remembers the result. Without it, plain direnv
rebuilds everything on every visit. Check it is set in `home.nix`, rebuild, then
run `direnv reload`.

### My project tools disappeared after a cleanup

nix-direnv marks the tools as in use inside the project's `.direnv/` folder. If
that folder was deleted, `nix-collect-garbage` had nothing telling it to keep
them. Run `direnv reload` to build it again.

### `uv` downloaded its own Python instead of the one I picked

The template sets `UV_PYTHON_DOWNLOADS=never` to stop exactly this. If you
removed that line, or changed `UV_PYTHON`, uv fetches its own Python and the
version you chose stops mattering. See [11-devshells.md](11-devshells.md).

### A downloaded program says "no such file or directory" but the file is there

The program is looking for a loader at `/lib64/ld-linux-x86-64.so.2`, which does
not exist on a Nix-managed system. Wrap it with `pkgs.buildFHSEnv`, or install it
with `apt` and accept that it sits outside the repeatable part.

## Neovim

### Copying does not reach Windows programs

Check what Neovim is using:

```
:checkhealth provider
```

It should say `WslClipboard`. If not, Neovim did not detect WSL. Confirm with
`:echo has('wsl')`.

Test the Windows program directly:

```bash
echo hello | clip.exe        # then paste anywhere in Windows
```

### Pasted lines end with `^M`

The part that removes the extra character is missing or broken. The `` `r ``
sequence uses a PowerShell backtick and is easy to damage when editing.

### Pasting is slow

Each paste starts `powershell.exe`, which takes about 100ms. That is the price
of `cache_enabled = 0`, which is what stops Neovim giving you old clipboard text.
Installing `win32yank` is the usual alternative if it bothers you.

### `gd` does nothing

No language server is set up. This config leaves that out on purpose.

### Plugins did not install

lazy.nvim downloads them the first time Neovim starts, and needs both network and
git. Run `:Lazy` to see what happened, or `:Lazy sync` to try again.

## herdr

### `herdr: command not found`

Not installed yet. Run `./rebuild.sh`. Then check it came from Nix and not from
their install script:

```bash
which herdr        # expect /nix/store/... or ~/.nix-profile/bin/herdr
```

### `hash mismatch in fixed-output derivation`

You changed `version` in `modules/herdr.nix` without changing the fingerprints.
The error shows both the expected and the real one. See
[03-modules-herdr-nix.md](03-modules-herdr-nix.md).

### Escape behaves strangely in Neovim inside herdr

Usually the mouse. `vim_config.lua` sets `o.mouse = ''` for exactly this reason.
If you turned the mouse back on, that is the cause.

### Sessions disappear after closing the terminal

They should not. herdr runs as a Linux program, separate from the terminal
window. But `wsl --shutdown`, or Windows fast startup, stops the whole Linux
machine and everything inside it. Check with `herdr status server`.

## AI tools

### `claude` runs an old version

Find out which copy is winning:

```bash
command -v claude && claude --version
```

If the answer is inside `/nix/store`, someone added `claude-code` back to
`home.packages`. Remove it. The Nix copy is frozen at whatever `flake.lock` says
and sits ahead of the self-updating one. See [08-agents.md](08-agents.md).

### A tool ignores `AGENTS.md`

Claude Code reads `~/.claude/CLAUDE.md`, which this repo does not manage. See
[08-agents.md](08-agents.md). For the tools it does manage, check the link
works:

```bash
ls -l ~/.codex/AGENTS.md
readlink -f ~/.codex/AGENTS.md
```

A broken link means `~/.dotfiles` is not pointing at the repo. Run
`./rebuild.sh`, which makes it again.

## General

### A tool is a different version from the one `home.nix` says

Something outside Nix is on your `PATH` first and winning. This is common with
Node, where nvm or fnm keeps its own copy. Check what you are really running:

```bash
command -v node      # want ~/.nix-profile/bin/node
```

To find every case of this at once:

```bash
./scripts/check-drift.sh
```

See [12-drift.md](12-drift.md).

### I added a package but the command is not found

The build has it, your profile does not. Run `./rebuild.sh`, then open a new
shell. `./scripts/check-drift.sh` lists everything in this state.

### Everything broke after I moved the repo

Every link goes through `~/.dotfiles`. Point it at the new place:

```bash
cd /new/path/to/dotfiles-wsl && ./rebuild.sh
```

### Undo a bad rebuild

```bash
home-manager generations              # newest first
/nix/store/<hash>-home-manager-generation/activate
```

### Start again from nothing

```bash
nix run home-manager/release-26.05 -- uninstall
/nix/nix-installer uninstall
```
