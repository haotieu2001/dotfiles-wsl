# 07 - herdr

herdr lets you run many terminals inside one window. It was built for working
with AI coding tools: each tool gets its own pane, and a sidebar shows whether it
is working, waiting for you, or finished.

There are two parts: the package
([03-modules-herdr-nix.md](03-modules-herdr-nix.md)) and the settings below,
which `home.nix` links straight from this repo.

## Why it suits WSL

herdr runs as a **Linux** program inside WSL, so its sessions do not depend on
the terminal window. Close the terminal, open it again, type `herdr`, and your
tools are still running exactly where you left them.

It also does the job the terminal program would normally do. That is why this
repo has no terminal settings at all. herdr gives you workspaces, tabs, panes and
sessions you can leave running, so the terminal only has to draw text quickly and
correctly. See [05-terminal.md](05-terminal.md).

The authors handle WSL directly too. For example, herdr draws its own cursor
under WSL, because the Windows one flickers.

## `home/.config/herdr/config.toml`, line by line

```toml
[keys]
prefix = "ctrl+b"
```

The key you press *before* any herdr command. `ctrl+b` is what tmux uses, chosen
here only so your fingers do not have to learn something new. If you never used
tmux, herdr's own defaults are fine and you can delete this whole section.

Be aware that `ctrl+b` normally means "move back one character" in a shell. While
herdr is running, it does not.

```toml
focus_pane_left  = "prefix+h"
focus_pane_down  = "prefix+j"
focus_pane_up    = "prefix+k"
focus_pane_right = "prefix+l"
```

Moving between panes with `hjkl`, the same directions Vim uses.

```toml
split_horizontal = "prefix+double_quote"
split_vertical    = "prefix+percent"
```

`prefix+"` and `prefix+%`, again from tmux. We write the key names out because
those characters need the Shift key.

One warning: the tmux names are backwards. `split_horizontal` draws a
*horizontal line*, which puts the two panes one above the other.

```toml
new_tab   = "prefix+c"
close_tab = "prefix+ampersand"
```

`prefix+c` makes a tab, `prefix+&` closes one. Both from tmux.

```toml
workspace_picker = "prefix+w"
goto             = "prefix+g"
```

`prefix+w` lists your workspaces, which are the top-level groups in the sidebar.
`prefix+g` opens a "jump to" box.

```toml
copy_mode  = "prefix+y"
```

Enters copy mode, where you can scroll back and select text with Vim keys. Only
the key that *enters* copy mode can be changed. Once inside, the keys are fixed:
`v` or space to select, `y` or Enter to copy, `q` or Escape to cancel.

Copy mode copies to the clipboard that herdr can reach. Getting text over to
Windows is a separate problem, which is why Neovim has its own solution for it.

```toml
[ui]
agent_panel_sort = "spaces"
```

How the sidebar is sorted. `"spaces"` groups tools by workspace. `"priority"`
moves the ones needing your attention to the top. We set it here rather than
relying on whatever the default happens to be.

## Using it with AI tools

```bash
herdr                       # start, or rejoin what is already running
```

Then `prefix+c` for a tab, `prefix+%` to split, and start a tool in a pane:

```bash
cc                          # claude --dangerously-skip-permissions
```

The sidebar shows what that pane is doing. This is the real benefit: you can see
at a glance which tools are busy and which are waiting for you, without visiting
each pane one by one.

Each tool needs its own small add-on:

```bash
herdr integration install claude
```

## How it fits with the rest of this setup

- **The mouse in Neovim.** `vim_config.lua` sets `o.mouse = ''`. This lets herdr
  leave mouse tracking off, which stops `Escape` being eaten while the terminal
  tries to work out a mouse movement. Turning the mouse back on in Neovim can
  bring that problem back.
- **Escape saves.** herdr passes `Escape` straight through, so the
  Escape-to-save key still works inside a herdr pane.
- **`.gitignore`.** herdr writes logs, a session file and sockets into its
  settings folder. Because that folder is linked into this repo, those files
  would otherwise show up in `git status`. We ignore them.

## Updating

Do **not** run `herdr update`. It writes into `~/.local/bin`, outside Nix, and
you end up with two copies. Change the version in `modules/herdr.nix` instead.
