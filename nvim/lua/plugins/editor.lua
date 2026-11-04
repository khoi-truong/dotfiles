return {
  {
    "echasnovski/mini.nvim",
    event = "VeryLazy",
    config = function()
      require("mini.icons").setup()
      MiniIcons.mock_nvim_web_devicons()
      require("mini.ai").setup()
      require("mini.surround").setup()
      require("mini.pairs").setup()
    end,
  },
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    keys = {
      {
        "<leader>ff",
        function()
          require("fzf-lua").files()
        end,
        desc = "Find files",
      },
      {
        "<leader>fg",
        function()
          require("fzf-lua").live_grep()
        end,
        desc = "Live grep",
      },
      {
        "<leader>fb",
        function()
          require("fzf-lua").buffers()
        end,
        desc = "Find buffers",
      },
    },
    opts = {},
  },
  {
    "stevearc/oil.nvim",
    lazy = false,
    keys = { { "-", "<Cmd>Oil<CR>", desc = "Open parent directory" } },
    opts = { default_file_explorer = true },
  },
  {
    "christoomey/vim-tmux-navigator",
    cond = vim.env.HERDR_ENV ~= "1",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
    },
    keys = {
      { "<C-h>", "<Cmd>TmuxNavigateLeft<CR>", desc = "Go to left window or pane" },
      { "<C-j>", "<Cmd>TmuxNavigateDown<CR>", desc = "Go to lower window or pane" },
      { "<C-k>", "<Cmd>TmuxNavigateUp<CR>", desc = "Go to upper window or pane" },
      { "<C-l>", "<Cmd>TmuxNavigateRight<CR>", desc = "Go to right window or pane" },
    },
  },
}
