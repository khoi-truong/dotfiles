return {
  -- Only its lsp/*.lua configs are used; config/lsp.lua enables the servers.
  { "neovim/nvim-lspconfig", lazy = false },
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
    },
  },
  {
    "saghen/blink.cmp",
    version = "1.*",
    -- Loaded at startup: its plugin/ file sets the LSP capabilities, which must be
    -- in place before the first client starts.
    lazy = false,
    opts = {
      keymap = { preset = "default" },
      fuzzy = { implementation = "prefer_rust_with_warning" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        per_filetype = { lua = { inherit_defaults = true, "lazydev" } },
        providers = {
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 100,
          },
        },
      },
    },
  },
}
