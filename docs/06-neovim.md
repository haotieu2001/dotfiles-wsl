# 06 - Neovim

A Neovim setup split into small files, managed by lazy.nvim. The one thing added
just for WSL is copy and paste.

`home.nix` links the whole folder, so every file below is edited in place. You
never need to rebuild after changing one.

```
home/.config/nvim/
├── init.lua                    # the start, three lines
└── lua/
    ├── vim_config.lua          # settings + WSL copy and paste
    ├── plugin.lua              # lazy.nvim setup
    ├── keys.lua                # my own keys
    └── plugins/                # one file per topic, loaded automatically
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

The order matters. `require('x')` looks for `lua/x.lua`.

`vim_config` runs first because it sets `vim.g.mapleader`. lazy.nvim works out
what `<leader>` means when it loads plugins, so setting the leader key *after*
loading them is the usual reason `<leader>` shortcuts quietly do nothing.

---

## `lua/vim_config.lua`

```lua
local o = vim.opt
vim.g.mapleader = ' '          -- space is the leader key
```

Space is the key you press first for your own shortcuts.

```lua
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent
o.number = true
o.relativenumber = true
```

Turning on both `number` and `relativenumber` gives you a mixed line-number
column: the line you are on shows its real number, and every other line shows how
far away it is. That distance is exactly the number you type to jump there, so a
line marked `5` above the cursor is `5k` away.

```lua
o.ignorecase = true            -- search ignores capitals
o.smartcase = true             -- unless i type a capital
```

Together: `/foo` finds any capitalisation, `/Foo` finds only `Foo`. `smartcase`
does nothing unless `ignorecase` is also on.

```lua
o.clipboard = 'unnamedplus'    -- use the system clipboard
```

Makes every copy and paste use the system clipboard, so you do not have to type
`"+y`. On WSL this alone is not enough. See below.

```lua
o.scrolloff = 16               -- keep the cursor away from the edge
o.undofile = true              -- remember undo history after closing
```

`scrolloff` keeps at least 16 lines visible above and below the cursor.
`undofile` saves undo history to disk, so you can still undo after closing a
file.

```lua
o.mouse = ''                   -- no mouse in nvim
```

Turns the mouse off. On purpose: with mouse reporting off, herdr can leave mouse
tracking off too, and then `Escape` is not eaten while the terminal tries to work
out a mouse movement.

### Copy and paste on WSL

```lua
if vim.fn.has('wsl') == 1 then
```

Neovim's own check for WSL, so this same setup still works on a real Linux
machine.

```lua
  local paste = 'powershell.exe -NoLogo -NoProfile -c '
    .. '[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
```

This is the reading half, and it is harder than writing. Windows stores copied
text with an extra invisible character at the end of every line. Without removing
it, every pasted line would arrive with a stray `^M`.

- `-NoProfile` skips your PowerShell startup file, which can add a few hundred
  milliseconds to every paste.
- `[Console]::Out.Write` writes the text exactly, unlike `Write-Output` which
  adds a newline.
- `` .replace("`r", "") `` removes the extra character. The backtick is
  PowerShell's escape symbol, so `` `r `` means "carriage return".

```lua
  vim.g.clipboard = {
    name = 'WslClipboard',
    copy = { ['+'] = 'clip.exe', ['*'] = 'clip.exe' },
    paste = { ['+'] = paste, ['*'] = paste },
    cache_enabled = 0,
  }
end
```

Tells Neovim how to reach the clipboard. `clip.exe` is a Windows program that
puts whatever you send it on the clipboard. WSL makes Windows programs available
from Linux, so we can call it directly.

Linux normally has two clipboards, `+` and `*`. Windows has only one, so both
point at the same place.

`cache_enabled = 0` matters. With caching on, Neovim would reuse the last thing
*it* copied instead of asking Windows. Then copying something in a Windows
program and pasting into Neovim would give you old text. The cost of turning it
off is one PowerShell start per paste, about 100ms. That is noticeable, and it is
why some people install `win32yank` instead. This repo prefers not to add another
program.

Check it works with `:checkhealth provider`. It should say `WslClipboard`.

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

The standard way to install lazy.nvim.

- `stdpath('data')` is `~/.local/share/nvim`, so plugins live outside this repo
  and are not saved in git.
- `--filter=blob:none` downloads the history without the file contents, and
  fetches those only when needed. Faster and smaller.
- `prepend` puts lazy.nvim first, so it can be loaded right away.
- `setup('plugins')` loads **every** file in `lua/plugins/`. That is why adding a
  plugin means adding a file and nothing else.

---

## `lua/keys.lua`

```lua
vim.keymap.set('n', '<Esc>', ':w<CR>', { desc = 'Save' })
```

Escape saves. The idea: leaving insert mode and wanting to save are almost
always the same moment.

```lua
vim.keymap.set('n', '<C-a>', 'ggVG', { desc = 'Select All' })
```

`gg` goes to the top, `V` starts selecting whole lines, `G` goes to the bottom.

```lua
vim.cmd([[ xnoremap <expr> p 'pgv"'.v:register.'y' ]])
```

This one is surprising but useful. Normally, pasting over selected text puts the
*replaced* text on the clipboard. So pasting a second time gives you the text you
just wrote over, instead of what you originally copied.

This changes paste-over-selection to: paste, select it again (`gv`), then copy it
back into the place it came from. The clipboard keeps its original contents, and
pasting repeatedly does what you expect.

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

`lazy = false` loads it at startup. `priority = 1000` loads it before other
plugins, so you never see a flash of default colours first. `name` sets what you
type in `require`, since the project is called `rose-pine/neovim`.

```lua
        transparency = string.find(vim.uv.os_uname().release, 'WSL') ~= nil,
```

On WSL the system version string looks like `6.18.x-microsoft-standard-WSL2`, so
looking for `WSL` is enough. A setup that also had to run on macOS would need an
extra check here.

Transparency stops Neovim painting its own background, so the terminal's
see-through effect shows through. Without it, the editor is a solid rectangle and
the blurred background is hidden behind it.

```lua
      vim.cmd('colorscheme rose-pine')

      local palette = require('rose-pine.palette')
      vim.api.nvim_set_hl(0, 'SnacksPickerDir', { fg = palette.subtle })
```

Applies the colours, then fixes one small readability problem: folder paths in
the file picker are too dim by default, so we set them to the theme's own
`subtle` colour.

---

## `lua/plugins/navigation.lua`

```lua
  {
    'stevearc/oil.nvim',
    opts = { view_options = { show_hidden = true } },
    keys = { { '<leader>e', '<cmd>Oil<cr>', desc = 'File Browser' } },
  },
```

oil.nvim shows a folder as an ordinary editable file. Rename by editing a line,
delete with `dd`, copy with `yy` then `p`, and `:w` applies your changes to the
real files.

Listing `keys` tells lazy.nvim to load the plugin the first time you press that
key, instead of at startup.

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

Snacks is a bundle of many small tools. `opts` turns on only the three we use:
the picker for finding things, the notifier for messages, and `input` for
prompts.

```lua
    keys = {
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
```

`<space>f` finds files, `<space>s` searches inside them, `<space>b` lists open
files, `gd` jumps to where something is defined. The search uses `ripgrep`, which
is why it is in `home.packages`.

`gd` needs a language server running to find anything. This setup does not
include one, on purpose.

---

## `lua/plugins/git.lua`

```lua
  {
    'NeogitOrg/neogit',
    dependencies = { 'nvim-lua/plenary.nvim', 'sindrets/diffview.nvim' },
    keys = { { '<leader>g', function() require('neogit').open() end, desc = 'Neogit' } },
  },
```

A full git screen on `<space>g`, for reading changes and choosing what to commit.
This is the main reason to open Neovim while AI tools are working.

```lua
  {
    'lewis6991/gitsigns.nvim',
    event = 'BufWinEnter',
    opts = { current_line_blame = true },
  },
```

Shows changed lines in the left margin, and who last changed the line you are on.

`event = 'BufWinEnter'` means: do not load this until a file is actually shown on
screen. That keeps startup fast.

---

## `lua/plugins/ui.lua`

```lua
  {
    'folke/which-key.nvim',
    lazy = false,
    config = true,
  },
```

Press `<space>` and wait: a small window lists every key you can press next.
`config = true` means "set it up with the default options".

This is why every shortcut above includes a `desc`. which-key shows that text.

---

## Plugin versions

lazy.nvim writes the exact versions it installed into `lazy-lock.json`. This repo
does not include that file, so plugins update freely. If you want them locked as
firmly as your Nix packages, run `:Lazy sync` and then commit
`home/.config/nvim/lazy-lock.json`.
