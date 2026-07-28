return {
  {
    'rose-pine/neovim',
    lazy = false,
    priority = 1000,
    name = 'rose-pine',
    config = function()
      require('rose-pine').setup({
        dark_variant = 'moon',
        dim_inactive_windows = false,
        extend_background_behind_borders = false,
        styles = {
          -- Let the terminal's own background show through, so WezTerm's
          -- window_background_opacity / Acrylic backdrop is visible behind
          -- the editor instead of nvim painting an opaque rectangle over it.
          -- On WSL, uname().release looks like "6.18.x-microsoft-standard-WSL2".
          italic = false,
          transparency = string.find(vim.uv.os_uname().release, 'WSL') ~= nil,
        },
      })

      vim.cmd('colorscheme rose-pine')

      -- Make the dimmed directory path in the Snacks picker readable
      local palette = require('rose-pine.palette')
      vim.api.nvim_set_hl(0, 'SnacksPickerDir', { fg = palette.subtle })
    end,
  },
}
