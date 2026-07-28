# 06 - Neovim

The video's 17:46 chapter. Structurally identical here; the one WSL-specific
addition is the clipboard bridge.

`home.nix` links the whole directory with `mkOutOfStoreSymlink`, so every file
below is live-edited. No rebuild after changing any of them.

```
home/.config/nvim/
├── init.lua                    # entry point, three requires
└── lua/
    ├── vim_config.lua          # options + WSL clipboard
    ├── plugin.lua              # lazy.nvim bootstrap
    ├── keys.lua                # personal keybinds
    └── plugins/                # one file per concern, auto-loaded
        ├── colorscheme.lua
        ├── navigation.lua
        ├── git.lua
        └── ui.lua
```

---

## `init.lua`

```lua
require('vim_config')
require('plugin')
require('keys')
```

Order matters. `require('x')` looks for `lua/x.lua` on the runtime path.

`vim_config` runs first because it sets `vim.g.mapleader`, and lazy.nvim resolves
`<leader>` in plugin keymaps at load time. Setting the leader after loading
plugins is the classic reason `<leader>` keybinds silently do nothing.

---

## `lua/vim_config.lua`

```lua
local o = vim.opt
vim.g.mapleader = ' '          -- space is the leader key
```

Space as the prefix for personal keybinds.

```lua
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent level
o.number = true
o.relativenumber = true
```

`number` plus `relativenumber` gives the hybrid gutter explained at 20:22: the
cursor line shows its absolute number, every other line shows its distance. That
distance is directly usable as a motion count, so a line marked `5` above the
cursor is `5k` away.

```lua
o.ignorecase = true            -- search is case-insensitive by default
o.smartcase = true             -- case-sensitive only if i type a capital
```

Together: `/foo` matches any case, `/Foo` matches only `Foo`. `smartcase`
requires `ignorecase` to have any effect.

```lua
o.clipboard = 'unnamedplus'    -- share the system clipboard
```

Makes every yank and put use the `+` register, i.e. the system clipboard, so no
`"+y` prefix is needed. On WSL this is not sufficient by itself; see below.

```lua
o.scrolloff = 16               -- keep cursor away from the screen edge
o.undofile = true              -- persistent undo across sessions
```

`scrolloff` keeps at least 16 lines of context above and below the cursor.
`undofile` writes undo history to disk, so undo survives closing the file.

```lua
o.mouse = ''                   -- no mouse in nvim
```

Disables mouse handling. Deliberate: with mouse reporting off, herdr keeps host
mouse capture off, and `Escape` is not swallowed by mouse-sequence parsing.

### The WSL clipboard bridge

```lua
if vim.fn.has('wsl') == 1 then
```

Neovim's own WSL detection, so the same config still works if you use it on a
real Linux machine.

```lua
  local paste = 'powershell.exe -NoLogo -NoProfile -c '
    .. '[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
```

The read side. Reading is harder than writing because Windows stores clipboard
text with CRLF line endings, and every pasted line would arrive with a trailing
`^M` if left alone.

- `-NoProfile` skips your PowerShell profile, which can cost hundreds of
  milliseconds per paste.
- `[Console]::Out.Write` writes raw, unlike `Write-Output` which appends a newline.
- `` .replace("`r", "") `` strips the CR. The backtick is PowerShell's escape
  character, so `` `r `` is a carriage return.

```lua
  vim.g.clipboard = {
    name = 'WslClipboard',
    copy = { ['+'] = 'clip.exe', ['*'] = 'clip.exe' },
    paste = { ['+'] = paste, ['*'] = paste },
    cache_enabled = 0,
  }
end
```

Registers a custom clipboard provider. `clip.exe` is a Windows binary that reads
stdin into the clipboard; WSL puts Windows executables on `PATH`, so it is
callable directly.

Both `+` (the clipboard) and `*` (the X primary selection) map to the same
place, since Windows has only one clipboard.

`cache_enabled = 0` matters. Caching would let Neovim reuse the last value it
wrote instead of shelling out, but then copying something in a Windows
application and pasting into Neovim would give you stale text. The cost is one
`powershell.exe` launch per paste, roughly 100ms - noticeable, and the reason
some people install `win32yank` instead. This repo prefers zero extra
dependencies.

Verify with `:checkhealth provider` - it should report `WslClipboard`.

---

## `lua/plugin.lua`

```lua
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git', '--branch=stable', lazypath })
end
vim.opt.rtp:prepend(lazypath)
require('lazy').setup('plugins')
```

The standard lazy.nvim bootstrap from the video at 22:45.

- `stdpath('data')` is `~/.local/share/nvim`, so plugins live outside this repo
  and are not committed.
- `--filter=blob:none` is a blobless clone: history without file contents,
  fetched on demand. Faster and smaller.
- `prepend` puts lazy.nvim at the front of the runtime path so it can be
  `require`d immediately.
- `setup('plugins')` loads **every** file in `lua/plugins/`, which is why adding
  a plugin means adding a file and nothing else.

---

## `lua/keys.lua`

```lua
vim.keymap.set('n', '<Esc>', ':w<CR>', { desc = 'Save' })
```

Escape saves. The reasoning at 31:02: leaving insert mode and wanting to save are
almost always the same moment.

```lua
vim.keymap.set('n', '<C-a>', 'ggVG', { desc = 'Select All' })
```

`gg` top, `V` linewise visual, `G` bottom.

```lua
vim.cmd([[ xnoremap <expr> p 'pgv"'.v:register.'y' ]])
```

The counterintuitive one from 32:07. By default, pasting over a visual selection
copies the replaced text into the unnamed register, so a second paste yields the
text you just overwrote instead of the original.

This remaps visual-mode `p` to paste, reselect (`gv`), and yank back into the
register it came from, so the register keeps its original content and repeated
pastes behave as you expect.

---

## `lua/plugins/colorscheme.lua`

```lua
return {
  {
    'rose-pine/neovim',
    lazy = false,
    priority = 1000,
    name = 'rose-pine',
```

A lazy.nvim spec. `lazy = false` loads at startup, `priority = 1000` loads it
before other plugins so no window is drawn with default colors first. `name`
sets the `require` path, since the repo is `rose-pine/neovim`.

```lua
        transparency = string.find(vim.uv.os_uname().release, 'WSL') ~= nil,
```

**Changed from the video**, which also tests for Darwin. On WSL the kernel
release string looks like `6.18.x-microsoft-standard-WSL2`, so matching `WSL` is
sufficient here.

Transparency makes Neovim skip painting a background, letting WezTerm's
opacity and Acrylic backdrop show through. Without it the editor is an opaque
rectangle and the terminal blur is invisible behind it.

```lua
      vim.cmd('colorscheme rose-pine')

      local palette = require('rose-pine.palette')
      vim.api.nvim_set_hl(0, 'SnacksPickerDir', { fg = palette.subtle })
```

Applies the scheme, then fixes one readability detail: the directory path in the
Snacks picker is too dim by default, so it is reset to the palette's `subtle`.

---

## `lua/plugins/navigation.lua`

```lua
  {
    'stevearc/oil.nvim',
    opts = { view_options = { show_hidden = true } },
    keys = { { '<leader>e', '<cmd>Oil<cr>', desc = 'File Browser' } },
  },
```

oil.nvim, the 26:15 chapter. It presents a directory as an ordinary editable
buffer: rename by editing a line, delete with `dd`, copy with `yy` then `p`, and
`:w` applies the changes to the filesystem.

Declaring `keys` makes lazy.nvim load the plugin on first use of that key rather
than at startup.

```lua
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = { enabled = true },
      notifier = { enabled = true },
      input = { enabled = true },
    },
```

Snacks is a collection; `opts` selects only the three pieces used here. The
picker is the fuzzy finder, the notifier replaces the message area, and `input`
replaces `vim.ui.input` prompts.

```lua
    keys = {
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
```

`<space>f` files, `<space>s` grep, `<space>b` buffers, `gd` go to definition.
The grep picker uses `ripgrep`, which is why it is in `home.packages`.

`gd` needs a running LSP server to return anything. This config does not set up
LSP, matching the video, which explicitly leaves it out at 33:04.

---

## `lua/plugins/git.lua`

```lua
  {
    'NeogitOrg/neogit',
    dependencies = { 'nvim-lua/plenary.nvim', 'sindrets/diffview.nvim' },
    keys = { { '<leader>g', function() require('neogit').open() end, desc = 'Neogit' } },
  },
```

A magit-style git UI on `<space>g`, for reviewing diffs and staging hunks. The
video's main reason for opening Neovim while working with agents.

```lua
  {
    'lewis6991/gitsigns.nvim',
    event = 'BufWinEnter',
    opts = { current_line_blame = true },
  },
```

Change markers in the gutter plus inline blame for the current line.

`event = 'BufWinEnter'` is the lazy-loading primitive explained at 28:53: do not
load this until a buffer is actually displayed in a window. Startup stays fast.

---

## `lua/plugins/ui.lua`

```lua
  {
    'folke/which-key.nvim',
    lazy = false,
    config = true,
  },
```

Press `<space>` and pause: a popup lists every key that can follow. `config = true`
means "call `require('which-key').setup({})` with defaults".

This is why every keymap above passes `desc` - which-key displays those strings.

---

## Plugin versions

lazy.nvim writes resolved commits to `lazy-lock.json`. This repo does not ship
one, matching the video. If you want plugins pinned as tightly as your Nix
packages, commit `home/.config/nvim/lazy-lock.json` after running `:Lazy sync`.
