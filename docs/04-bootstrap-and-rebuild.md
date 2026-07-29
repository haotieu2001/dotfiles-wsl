# 04 - `bootstrap.sh` and `rebuild.sh`

Two scripts: one you run once, one you run forever after.

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

The font install runs after every switch. It is cheap and idempotent, so the
font on the Windows side cannot drift from the one `flake.lock` pins.

Note what `rebuild.sh` does **not** call:
`scripts/apply-windows-terminal-theme.sh`. The theme is seeded once by
`bootstrap.sh` and then belongs to you. Reasoning in
[05-terminal.md](05-terminal.md).

- `set -euo pipefail` - exit on any failing command (`e`), on any undefined
  variable (`u`), and on a failure anywhere in a pipeline rather than only at
  its end (`pipefail`). Without this a mid-script failure would be ignored and
  the script would report success.
- `DIR=...` - the absolute, symlink-resolved (`pwd -P`) directory of this
  script, so it works no matter where you invoke it from.
- `ln -sfn "$DIR" ~/.dotfiles` - recreate the stable path. `-s` symbolic, `-f`
  replace an existing link, `-n` treat an existing link to a directory as a file
  to replace rather than descending into it. Without `-n` you would eventually
  create `~/.dotfiles/dotfiles-wsl`.
- `exec` on the final line - replace the shell with the font script instead of
  forking, so its exit code becomes the script's directly.
- `--flake ~/.dotfiles#wsl` - build the `homeConfigurations."wsl"` output.
- `-b backup` - if activation is about to overwrite a file it does not manage
  (typically `~/.bashrc` or `~/.profile`), rename it to `<name>.backup` instead
  of aborting. Standalone home-manager fails hard on collisions without this,
  which is a very common first-run stumble.

**No `sudo`.** `nixos-rebuild` and `darwin-rebuild` need it because they edit
system state. This one only writes `$HOME`, and running it as root would build
the config into `/root`.

---

# `bootstrap.sh`

Idempotent: safe to re-run at any point.

### Step 0 - confirm WSL

```bash
if ! grep -qi microsoft /proc/version 2>/dev/null; then
```

`/proc/version` contains "microsoft" under WSL. Only a warning, since everything
except the Windows-side steps works on any Linux box.

### Step 1 - systemd

```bash
if [ -d /run/systemd/system ]; then
```

The standard test for "systemd is actually running as PID 1", not merely
installed. Multi-user Nix runs `nix-daemon`, and the Determinate installer
registers it as a systemd unit; without an init system there is nothing to start
it and Nix will not work.

```bash
  if ! grep -q 'systemd *= *true' /etc/wsl.conf 2>/dev/null; then
    sudo tee -a /etc/wsl.conf >/dev/null <<'WSLCONF'

[boot]
systemd=true
WSLCONF
  fi
```

Appends the boot section, guarded so re-running does not add it twice. Quoting
the heredoc delimiter (`<<'WSLCONF'`) keeps the content literal.

The script then **exits 1**, because `/etc/wsl.conf` is only read when the distro
starts. You must run `wsl --shutdown` from PowerShell and reopen Ubuntu. This is
the single most common place to get stuck; it is not a failure.

### Step 2 - Determinate Nix

```bash
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
```

The Determinate installer supports WSL2 directly. The curl flags matter:
`--proto '=https'` refuses a plaintext redirect, `--tlsv1.2` sets a TLS floor,
`-f` makes HTTP errors non-zero instead of piping an error page into `sh`.

`--no-confirm` skips the interactive prompt, since bootstrap already asked you
to run it.

The trailing `.` sources the profile script so `nix` is on `PATH` for the rest of
*this* script; new shells get it automatically.

Determinate enables flakes by default, which is why nothing here sets
`experimental-features`.

### Step 3 - the `~/.dotfiles` symlink

Identical to `rebuild.sh`, and it must happen **before** the first switch:
`home.nix` builds its `mkOutOfStoreSymlink` targets from that path.

### Step 4 - personalize the username

```bash
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
```

Reads the `user = "..."` line back out of `flake.nix`. If you reformat that line,
this stops matching, which is why `flake.nix` calls it out.

```bash
    sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
```

Rewrites it in place. Note this is GNU sed: `-i` takes no argument. BSD sed, as
found on macOS, requires an explicit backup-suffix (`sed -i '' -E`), so a line
copied from a macOS script fails here and vice versa.

No `sudo` runs before this point, so `whoami` is reliable here.

### Step 5 - the first switch

```bash
NIX_BIN="$(command -v nix)"
"$NIX_BIN" run home-manager/release-26.05 -- \
  switch --flake ~/.dotfiles#wsl -b backup
```

`home-manager` is not on `PATH` yet, so it is run straight from its flake this
once. After this switch, `programs.home-manager.enable = true` has installed the
command properly and `rebuild.sh` works.

The `--` separates arguments to `nix run` from arguments to home-manager.

The branch here (`release-26.05`) should match `flake.nix`. Note this fetches
the *tool* from that branch; the configuration it applies is still pinned by
your `flake.lock`.

This is the slow step on a fresh machine.

### Step 6 - zsh as the login shell

```bash
ZSH_BIN="$HOME/.nix-profile/bin/zsh"
```

The home-manager zsh, not an apt one. Using the Nix build is what makes the
shell reproducible.

```bash
  if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  fi
  chsh -s "$ZSH_BIN" || { ... }
```

`chsh` refuses any shell absent from `/etc/shells`, so it is registered first.
`grep -qxF` matches the whole line, literally, so a partial match cannot cause a
duplicate entry.

`chsh` prompts for your password and can fail under some WSL PAM configurations.
The fallback printed on failure is to append `exec ~/.nix-profile/bin/zsh -l` to
`~/.bashrc`, which achieves the same result at login.

This step exists because Ubuntu logs you into bash. A distro that already
defaults to zsh would not need it.

### Step 7 - the font

```bash
"$DIR/scripts/install-windows-font.sh" || \
  echo "    Font install failed; run ./scripts/install-windows-font.sh later."
```

Pushes the font across to Windows. There is no separate PowerShell step: WSL can
call Windows executables and write to the Windows filesystem, so this runs
inside the same bootstrap.

The `||` matters. A missing font is a cosmetic problem, not a reason to fail a
bootstrap that has already installed everything else successfully. Covered in
[09-windows-bridge.md](09-windows-bridge.md).

### Step 8 - seed the terminal theme

```bash
"$DIR/scripts/apply-windows-terminal-theme.sh" || \
  echo "    Theme not applied; run ./scripts/apply-windows-terminal-theme.sh later."
```

**The only place this script is ever called automatically.** It merges the
colour scheme and profile defaults from `windows/` into Windows Terminal's
`settings.json`, backing the file up first.

It is a no-op if the scheme is already there, which is what makes re-running
bootstrap safe: your terminal customisations are never silently reverted. The
same `||` guard applies for the same reason.

Full reasoning for why this runs at bootstrap and not at rebuild is in
[05-terminal.md](05-terminal.md).

## Re-running

Every step is guarded, so re-running is a cheap way to repair a partial setup.
The only step that changes anything on a second run is step 5, which rebuilds.
Step 8 explicitly does nothing once the theme has been seeded.
