# 10 - Troubleshooting

Failure modes specific to running this setup on WSL rather than macOS.

## Install

### `bootstrap.sh` exits telling me to run `wsl --shutdown`

Working as intended. `/etc/wsl.conf` is read only at distro start, so enabling
systemd needs a restart. From **PowerShell**, not inside WSL:

```powershell
wsl --shutdown
```

Reopen Ubuntu and re-run `./bootstrap.sh`. Confirm with:

```bash
systemctl is-system-running     # "running" or "degraded" are both fine
```

### `nix: command not found` right after installing Nix

The installer adds Nix to *new* shells. Either open a new shell, or:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### `error: experimental Nix feature 'nix-command' is disabled`

Nix came from somewhere other than the Determinate installer. Either reinstall
with it, or:

```bash
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

### `Existing file '/home/you/.bashrc' would be clobbered`

home-manager refuses to overwrite files it does not manage. Both scripts already
pass `-b backup` to rename them instead. If you hit this, you ran home-manager
by hand without that flag - use `./rebuild.sh`.

### `Could not resolve host` during the first build

```
> trying https://github.com/ogulcancelik/herdr/releases/download/v0.7.5/herdr-linux-x86_64
> curl: (6) Could not resolve host: github.com
error: cannot download herdr-linux-x86_64 from any mirror
```

**Almost always transient. Re-run `./bootstrap.sh`.** Since Nix caches what it
already fetched, the retry resumes rather than starting over. `bootstrap.sh`
now retries the switch three times on its own.

The cause is a WSL timing quirk, not a misconfiguration. WSL routes DNS through
a proxy on the Windows host (typically `10.255.255.254`, see `/etc/resolv.conf`),
and that proxy is briefly unreachable while the Nix daemon and systemd units
settle right after Step 2 installs Nix. Flake inputs are fetched by the daemon
and usually land before the gap; fixed-output derivations like `herdr`
download inside the build sandbox moments later and hit it.

The giveaway is that every retry fails inside a few seconds, and packages that
came from `cache.nixos.org` in the same run succeeded.

If it persists, confirm DNS actually works from inside the sandbox rather than
just from your shell:

```bash
nix build --impure --no-link --expr '
  (import <nixpkgs> {}).runCommand "dnsprobe" {
    outputHashMode = "flat"; outputHashAlgo = "sha256";
    outputHash = "0000000000000000000000000000000000000000000000000000000000000000";
    nativeBuildInputs = [ (import <nixpkgs> {}).curl ];
  } "cat /etc/resolv.conf 1>&2; curl -sS --connect-timeout 10 -o /dev/null http://cache.nixos.org/ 2>&1; exit 1"
'
```

Read the log it prints. A nameserver line plus no `curl: (6)` means DNS is fine
inside the sandbox and the earlier failure was the timing gap. A genuinely
broken setup shows an empty or missing `resolv.conf`.

Only if it is genuinely and repeatedly broken, give the sandbox a stable
resolver by replacing the WSL-generated symlink:

```bash
sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'

[network]
generateResolvConf = false
EOF
sudo rm -f /etc/resolv.conf
printf 'nameserver 10.255.255.254\nnameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf >/dev/null
```

Keep the WSL proxy first so split-DNS on a VPN or corporate network still
resolves internal names. Then `wsl --shutdown` from PowerShell.

### The first build is extremely slow

Expected once. If it is slow *every* time, check the repo is not on `/mnt/c`:

```bash
pwd -P      # should start with /home, not /mnt
```

### `error: attribute 'wsl' missing`

The flake fragment does not match. `flake.nix` must define
`homeConfigurations."wsl"` and the scripts must use `#wsl`.

### `error: Package '<name>' has an unfree license`

You added a package with a non-free license. `config.allowUnfree = true` is
missing from the `import nixpkgs` block in `flake.nix`, or nixpkgs was pulled in
via `legacyPackages`, which ignores config.

## Shell

### Still in bash after bootstrap

Check what step 6 did:

```bash
getent passwd "$USER" | cut -d: -f7
```

If it is not the Nix zsh, run it manually:

```bash
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
```

`chsh` needs your **UNIX password**, not sudo, and fails under some WSL PAM
setups. Note that `sudo tee` succeeding tells you nothing about whether `chsh`
did: in the combined one-liner the first half can work while the second fails.
Run `chsh` on its own to see the actual error.

If it will not work, `bootstrap.sh` falls back to launching zsh from
`~/.bashrc`. To do it by hand, append **this**, not a bare `exec`:

```bash
if shopt -q login_shell && [[ $- == *i* ]] && [ -t 0 ] \
   && [ -z "${ZSH_VERSION:-}" ] && [ -x "$HOME/.nix-profile/bin/zsh" ]; then
  exec "$HOME/.nix-profile/bin/zsh" -l
fi
```

The `shopt -q login_shell` test is the important one. A bare
`exec zsh -l` in `~/.bashrc` also fires for *non-login* interactive shells, so
any tool that runs `bash -ic "some command"` gets zsh exec'd over it, loses the
command, and hangs forever. `[ -t 0 ]` keeps it out of pipelines.

Log out and back in either way; `chsh` does not affect the current session.

### /etc/shells has duplicate zsh entries

Harmless, but from re-running the registration. Tidy up with:

```bash
sudo cp /etc/shells /etc/shells.bak
sudo awk '!seen[$0]++' /etc/shells.bak | sudo tee /etc/shells >/dev/null
```

### Aliases or `$EDITOR` did not update

`sessionVariables` are exported at session start. Open a new shell.

### Prompt shows boxes or missing glyphs

Starship's symbols need a Nerd Font **on Windows**. Run
`./scripts/install-windows-font.sh`, then sign out of Windows and back in;
newly registered fonts are often invisible to already-running processes.

## Terminal

### Colours or font did not change

Run the sync by hand and read what it says:

```bash
./scripts/install-windows-font.sh
```

`no Windows Terminal profile named '<distro>' yet` means Windows Terminal has
never generated a profile for this distro. Open it once, then re-run.

`settings.json is not valid JSON (comments?)` means the script refused to touch
your config rather than risk corrupting it. Open Windows Terminal, change any
setting so it rewrites the file as plain JSON, then re-run.

### I want my old terminal settings back

```
<Windows profile>\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.dotfiles-backup
```

Written before any change. The sync only ever adds its own scheme and patches
the one WSL profile, so unrelated profiles and schemes are already preserved.

### Boxes instead of glyphs

The font is registered but Windows has not picked it up. Sign out and back in.
Verify it registered:

```bash
reg.exe query 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' | grep -i hack
```

### Background is opaque

`opacity` must be below 100, set in Windows Terminal's own settings. This repo does not manage it.
If the terminal is translucent but Neovim is not, the colourscheme
`transparency` flag is false - see [06-neovim.md](06-neovim.md).

### Starts in /mnt/c/...

The zsh guard in `home.nix` bounces you to `$HOME`. If it is not firing, you are
probably still on bash; finish the `chsh` step.

## Neovim

### Yank does not reach Windows apps

Check the provider:

```
:checkhealth provider
```

It should report `WslClipboard`. If not, `vim.fn.has('wsl')` returned 0 - confirm
with `:echo has('wsl')`.

Test the underlying binaries directly:

```bash
echo hello | clip.exe        # then paste anywhere in Windows
```

### Pasted lines end with `^M`

The CR strip in the paste command is missing or mangled. The `` `r `` sequence
uses a PowerShell backtick escape and is easy to break when editing.

### Paste is noticeably slow

Each paste launches `powershell.exe` (~100ms). That is the cost of
`cache_enabled = 0`, which is what keeps Neovim from serving stale clipboard
content. Installing `win32yank` is the usual alternative if it bothers you.

### `gd` does nothing

No LSP server is configured. This matches the video, which leaves LSP out.

### Plugins did not install

lazy.nvim clones on first launch and needs network plus git. Run `:Lazy` to see
the state, `:Lazy sync` to force.

## herdr

### `herdr: command not found`

Not in the profile yet - run `./rebuild.sh`. Then confirm it came from Nix, not
from an upstream install script:

```bash
which herdr        # expect /nix/store/... or ~/.nix-profile/bin/herdr
```

### `hash mismatch in fixed-output derivation`

You bumped `version` in `modules/herdr.nix` without updating the hashes. The
error prints both expected and actual; see
[03-modules-herdr-nix.md](03-modules-herdr-nix.md).

### Escape behaves oddly in Neovim inside herdr

Usually mouse reporting. `vim_config.lua` sets `o.mouse = ''` for exactly this
reason; if you enabled the mouse, that is the cause.

### Sessions vanish after closing the terminal

They should not - the server is a Linux process independent of the terminal. But
`wsl --shutdown`, or Windows fast startup, stops the whole VM and everything in
it. Check for leftover state with `herdr status server`.

## Agents

### `claude` runs an old version

Check which one is winning:

```bash
command -v claude && claude --version
```

If it resolves inside `/nix/store`, something added `claude-code` back to
`home.packages`. Remove it - the Nix copy is frozen at `flake.lock` and sits
ahead of the self-updating `~/.local/bin/claude` on `PATH`. See
[08-agents.md](08-agents.md).

### An agent ignores `AGENTS.md`

Claude Code reads `~/.claude/CLAUDE.md`, which this repo does not manage - see
[08-agents.md](08-agents.md). For the agents it does manage, check the symlink
resolves:

```bash
ls -l ~/.codex/AGENTS.md
readlink -f ~/.codex/AGENTS.md
```

A dangling link means `~/.dotfiles` does not point at the repo. Run
`./rebuild.sh`, which recreates it.

## General

### Everything is dangling after moving the repo

Every symlink resolves through `~/.dotfiles`. Re-point it:

```bash
cd /new/path/to/dotfiles-wsl && ./rebuild.sh
```

### Roll back a bad rebuild

```bash
home-manager generations              # list, newest first
/nix/store/<hash>-home-manager-generation/activate
```

### Start completely over

```bash
nix run home-manager/release-26.05 -- uninstall
/nix/nix-installer uninstall
```
