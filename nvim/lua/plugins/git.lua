return {
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      {
        "<leader>gb",
        function()
          require("gitsigns").blame_line({ full = true })
        end,
        desc = "Blame line",
      },
    },
    opts = {},
  },
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = { { "<leader>xx", "<Cmd>Trouble diagnostics toggle<CR>", desc = "Diagnostics list" } },
    opts = {},
  },
}
