# 04 - The two scripts

`bootstrap.sh` you run once. `rebuild.sh` you run forever after.

---

# `rebuild.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
home-manager switch --flake ~/.dotfiles#wsl -b backup
exec "$DIR/scripts/install-windows-font.sh"
```

The font is copied to Windows after every rebuild. It is quick, and running it
twice changes nothing, so the font on the Windows side can never drift from the
one Nix installed.

Notice what `rebuild.sh` does **not** run:
`scripts/apply-windows-terminal-theme.sh`. Your terminal colours are set once by
`bootstrap.sh` and then belong to you. See [05-terminal.md](05-terminal.md).

Line by line:

- `set -euo pipefail` - stop as soon as anything fails (`e`), stop if a variable
  was never set (`u`), and notice a failure anywhere in a chain of commands, not
  just at the end (`pipefail`). Without this, a failure in the middle would be
  ignored and the script would claim success.
- `DIR=...` - the real folder this script lives in, with any links resolved
  (`pwd -P`). This way it works no matter where you run it from.
- `ln -sfn "$DIR" ~/.dotfiles` - make the link again. `-s` means a symbolic link,
  `-f` replaces one that already exists, and `-n` is the important one: without
  it you would eventually create `~/.dotfiles/dotfiles-wsl` by mistake.
- `exec` on the last line - replace this script with the font script instead of
  starting a second one, so its result becomes the result of the whole script.
- `--flake ~/.dotfiles#wsl` - build the `homeConfigurations."wsl"` part.
- `-b backup` - if the rebuild is about to overwrite a file it does not manage,
  usually `~/.bashrc` or `~/.profile`, rename the old one to `<name>.backup`
  instead of stopping. Without this, home-manager fails outright, which trips up
  almost everyone on their first run.

**No `sudo`.** `nixos-rebuild` and `darwin-rebuild` need it because they change
the system. This one only writes inside your home folder. Running it as root
would build everything into `/root` instead.

---

# `bootstrap.sh`

Safe to run again at any point.

### Step 0 - check you are on WSL

```bash
if ! grep -qi microsoft /proc/version 2>/dev/null; then
```

On WSL, the file `/proc/version` contains the word "microsoft". This only warns
you, because everything except the Windows steps works on any Linux machine.

### Step 1 - systemd

```bash
if [ -d /run/systemd/system ]; then
```

This checks that systemd is actually running, not just installed. Nix runs a
background service, and the Determinate installer starts it through systemd.
Without systemd there is nothing to start it, and Nix will not work.

```bash
  if ! grep -q 'systemd *= *true' /etc/wsl.conf 2>/dev/null; then
    sudo tee -a /etc/wsl.conf >/dev/null <<'WSLCONF'

[boot]
systemd=true
WSLCONF
  fi
```

Adds the setting, and checks first so running twice does not add it twice.
The quotes in `<<'WSLCONF'` keep the text exactly as written.

The script then **stops with an error**, because `/etc/wsl.conf` is only read
when the distro starts. Run `wsl --shutdown` from PowerShell and open Ubuntu
again. This is the most common place to get stuck, and it is not a failure.

### Step 2 - install Nix

```bash
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
```

The Determinate installer supports WSL2 directly. The `curl` options matter:
`--proto '=https'` refuses to fall back to an unencrypted connection,
`--tlsv1.2` sets a minimum security level, and `-f` makes a web error a real
error instead of piping an error page into the shell.

`--no-confirm` skips the yes/no question, since bootstrap already asked you to
run this.

The lone `.` at the start of the last line loads the Nix settings so that `nix`
works for the rest of *this* script. New shells pick it up by themselves.

Determinate turns on flakes for you, which is why nothing here sets
`experimental-features`.

### Step 3 - the `~/.dotfiles` link

The same as in `rebuild.sh`, and it must happen **before** the first build.
`home.nix` builds its link targets from that path.

### Step 4 - set your username

```bash
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
```

Reads the `user = "..."` line back out of `flake.nix`. If you change the spacing
on that line, this stops finding it, which is why `flake.nix` warns you.

```bash
    sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
```

Changes it in place. Note this is GNU sed, where `-i` takes no extra value. The
sed on macOS needs `sed -i '' -E` instead, so a line copied from a macOS script
fails here, and the other way round.

No `sudo` has run yet at this point, so `whoami` gives the right answer.

### Step 5 - the first build

```bash
NIX_BIN="$(command -v nix)"
"$NIX_BIN" run home-manager/release-26.05 -- \
  switch --flake ~/.dotfiles#wsl -b backup
```

`home-manager` is not installed yet, so we run it straight from the internet
this one time. After this build finishes, `programs.home-manager.enable = true`
has installed the command properly and `rebuild.sh` works.

The `--` separates options for `nix run` from options for home-manager.

The branch here (`release-26.05`) should match `flake.nix`. This only picks the
*tool*; the settings it applies still come from your `flake.lock`.

This is the slow step on a new computer.

### Step 6 - make zsh your shell

```bash
ZSH_BIN="$HOME/.nix-profile/bin/zsh"
```

The zsh that home-manager installed, not one from apt. Using the Nix one is what
makes your shell the same on every computer.

```bash
  if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  fi
  chsh -s "$ZSH_BIN" || { ... }
```

`chsh` refuses any shell that is not listed in `/etc/shells`, so we add it
first. `grep -qxF` matches the whole line exactly, so a partial match cannot
create a duplicate entry.

`chsh` asks for your password and fails on some WSL setups. If it does, the
script adds a line to `~/.bashrc` that starts zsh at login instead, which needs
no password.

This step exists because Ubuntu starts you in bash. A system that already uses
zsh would not need it.

### Step 7 - the font

```bash
"$DIR/scripts/install-windows-font.sh" || \
  echo "    Font install failed; run ./scripts/install-windows-font.sh later."
```

Copies the font to Windows. There is no separate PowerShell step: WSL can run
Windows programs and write to the Windows disk, so this happens right here.

The `||` matters. A missing font is only a cosmetic problem, not a reason to
fail an install that has already worked.
See [09-windows-bridge.md](09-windows-bridge.md).

### Step 8 - set the terminal colours

```bash
"$DIR/scripts/apply-windows-terminal-theme.sh" || \
  echo "    Theme not applied; run ./scripts/apply-windows-terminal-theme.sh later."
```

**The only place this script ever runs by itself.** It adds the colours and font
settings from `windows/` into Windows Terminal's `settings.json`, saving a copy
of the old file first.

It does nothing if your colours are already there. That is what makes running
bootstrap again safe: your terminal changes are never undone. The `||` is there
for the same reason as above.

The full reasoning for why this runs at install and not at rebuild is in
[05-terminal.md](05-terminal.md).

## Running it again

Every step checks first, so running bootstrap again is a cheap way to fix a
half-finished setup. The only step that does real work the second time is step 5,
which rebuilds. Step 8 does nothing once your colours are set.
