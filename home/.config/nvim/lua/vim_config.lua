local o = vim.opt
vim.g.mapleader = ' '          -- space is the leader key
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent level
o.number = true                -- absolute number on the cursor line, relative elsewhere
o.relativenumber = true        -- relative line numbers for fast jumps
o.ignorecase = true            -- search is case-insensitive by default
o.smartcase = true             -- case-sensitive only if i type a capital
o.clipboard = 'unnamedplus'    -- share the system clipboard
o.scrolloff = 16               -- keep cursor away from the screen edge
o.undofile = true              -- persistent undo across sessions
o.mouse = ''                   -- no mouse in nvim; also lets herdr keep host mouse capture off so Escape isn't swallowed

-- WSL clipboard bridge.
--
-- On macOS `clipboard = 'unnamedplus'` just works, because nvim finds pbcopy.
-- A WSL Linux VM has no X selection wired to the Windows clipboard, so nvim
-- would silently yank into a void. Route through the Windows binaries instead:
--   clip.exe       - write to the Windows clipboard
--   powershell.exe - read it back, stripping the CRLF that Windows adds
-- Without the \r strip, every pasted line arrives with a trailing ^M.
if vim.fn.has('wsl') == 1 then
  local paste = 'powershell.exe -NoLogo -NoProfile -c '
    .. '[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
  vim.g.clipboard = {
    name = 'WslClipboard',
    copy = { ['+'] = 'clip.exe', ['*'] = 'clip.exe' },
    paste = { ['+'] = paste, ['*'] = paste },
    -- Each paste shells out to powershell.exe (~100ms). Caching would serve
    -- stale text after you copy something in a Windows app, so leave it off.
    cache_enabled = 0,
  }
end
