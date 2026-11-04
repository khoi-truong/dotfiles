return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-neotest/neotest-python",
      "fredrikaverpil/neotest-golang",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      {
        "<leader>tt",
        function()
          require("neotest").run.run()
        end,
        desc = "Test nearest",
      },
    },
    config = function()
      require("neotest").setup({
        adapters = { require("neotest-python"), require("neotest-golang") },
      })
    end,
  },
}
