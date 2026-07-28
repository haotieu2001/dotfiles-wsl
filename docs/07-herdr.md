# 07 - herdr

The video's 33:22 chapter. herdr is a terminal multiplexer built for the agent
era: it gives each agent its own pane and tracks whether that agent is working,
blocked, or done in a sidebar.

Two parts: the package ([03-modules-herdr-nix.md](03-modules-herdr-nix.md)) and
the config below, symlinked live by `home.nix`.

## Why it fits WSL well

The video mentions herdr may be the only multiplexer that also works on Windows.
For this setup that matters in a specific way: it runs as a **Linux** process
inside WSL, so its sessions survive independently of whichever terminal window is
attached. Close the terminal, reopen it, run `herdr`, and your agents are still
running exactly where you left them.

It also does the job the terminal emulator would otherwise do. That is why this
port does not carry over the video's WezTerm config: with herdr providing
workspaces, tabs, panes and detachable sessions, the host terminal only has to
be a fast, correct VT renderer. See [05-terminal.md](05-terminal.md).

Upstream also handles WSL explicitly, for example defaulting to its own drawn
cursor under WSL to avoid host cursor flicker.

## `home/.config/herdr/config.toml`, line by line

```toml
[keys]
prefix = "ctrl+b"
```

The prefix key, pressed before any multiplexer command. `ctrl+b` is the tmux
default, chosen here purely to preserve muscle memory. If you never used tmux,
herdr's own defaults are reasonable and you can delete this whole section.

Be aware `ctrl+b` is "move back one character" in a readline shell, so it is
shadowed while herdr is running.

```toml
focus_pane_left  = "prefix+h"
focus_pane_down  = "prefix+j"
focus_pane_up    = "prefix+k"
focus_pane_right = "prefix+l"
```

Pane movement on `hjkl`, matching Vim's directions.

```toml
split_horizontal = "prefix+double_quote"
split_vertical    = "prefix+percent"
```

`prefix+"` and `prefix+%`, the tmux bindings. Written as key names because the
characters are shifted.

Note the tmux naming is famously backwards: `split_horizontal` produces a
horizontal *divider*, i.e. panes stacked vertically.

```toml
new_tab   = "prefix+c"
close_tab = "prefix+ampersand"
```

`prefix+c` creates, `prefix+&` closes, both from tmux.

```toml
workspace_picker = "prefix+w"
goto             = "prefix+g"
```

`prefix+w` lists workspaces, the top-level grouping in the sidebar.
`prefix+g` is the jump-to prompt.

```toml
copy_mode  = "prefix+y"
```

Enters copy mode for scrolling back and selecting text with Vim motions. Only
the *entry* key is configurable; inside copy mode the keys are fixed (`v` or
space to select, `y` or Enter to copy, `q` or Escape to cancel).

Copy mode writes to the clipboard herdr can reach. Crossing into Windows is a
separate step, which is why Neovim has its own clipboard bridge.

```toml
[ui]
agent_panel_sort = "spaces"
```

Sidebar ordering: `"spaces"` groups agents by workspace, `"priority"` floats
agents needing attention to the top. Set explicitly rather than relying on the
default.

## Using it with agents

```bash
herdr                       # start or attach
```

Then `prefix+c` for a tab, `prefix+%` to split, and run an agent in a pane:

```bash
cc                          # claude --dangerously-skip-permissions
```

The sidebar shows that pane's live state. That is the payoff described at 38:32:
you can see at a glance which agents are working and which are waiting for you,
without switching to each pane.

Agent integrations are installed per agent:

```bash
herdr integration install claude
```

## Interaction with the rest of this setup

- **Neovim mouse.** `vim_config.lua` sets `o.mouse = ''` so herdr can keep host
  mouse capture off, which stops `Escape` being swallowed by mouse-sequence
  parsing. Enabling the mouse in Neovim can bring that back.
- **Escape as save.** herdr passes `Escape` through as its own key, so the
  Escape-to-save binding works inside herdr panes.
- **`.gitignore`.** herdr writes logs, a session file, and sockets into its
  config directory. Since that directory is a live symlink into the repo, those
  runtime artifacts would otherwise show up in `git status`. They are ignored.

## Upgrading

Do **not** run `herdr update`: it writes to `~/.local/bin`, outside Nix, leaving
two binaries on `PATH`. Bump the pinned version in `modules/herdr.nix` instead.
