-- The servers themselves are installed by bootstrap.sh, not by mason.
--
-- mason downloads its own binaries into ~/.local/share/nvim: absent on the next
-- machine and invisible to the repo. Installing them in bootstrap.sh (npm and uv
-- globals, plus lua-language-server pinned in packages/pinned.sh) keeps a
-- language server as reproducible as ripgrep, and scripts/check-drift.sh checks
-- they are there.
--
-- nvim-lspconfig is still wanted, but only for the per-server *config* - the
-- command to run, which filetypes it claims, which files mark a project root.
-- Since 0.11 Neovim reads those itself through vim.lsp.enable, so there is no
-- setup() call and no on_attach boilerplate here.
--
-- A server that is enabled but not installed is silently skipped, so trimming
-- the install list in bootstrap.sh degrades gracefully.
return {
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      -- Editing this config is the main Lua anyone does here, so teach lua_ls
      -- about the globals it would otherwise flag on every line.
      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            diagnostics = { globals = { 'vim', 'Snacks' } },
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      })

      vim.lsp.enable({
        'lua_ls',       -- this config
        'basedpyright', -- python
        'ts_ls',        -- javascript, typescript
        'bashls',       -- bootstrap.sh and the scripts/
      })
    end,
  },
}
