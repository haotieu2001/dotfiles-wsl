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
          italic = false,
          -- Let the terminal's own background show through instead of nvim
          -- painting an opaque rectangle over it. Windows Terminal is the
          -- thing being seen through here: windows/profile-defaults.json sets
          -- opacity 80 and a background image, and both disappear behind an
          -- opaque editor.
          -- On WSL, uname().release looks like "6.18.x-microsoft-standard-WSL2".
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
