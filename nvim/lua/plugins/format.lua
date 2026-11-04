return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ lsp_format = "fallback" })
        end,
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format", "ruff_organize_imports" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        zsh = { "shfmt" },
        go = { "goimports", "gofmt", stop_after_first = true },
        swift = { "swiftformat" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
      },
      format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
      notify_on_error = false,
      notify_no_formatters = false,
    },
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = { sh = { "shellcheck" }, swift = { "swiftlint" } }
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("dotfiles-lint", { clear = true }),
        desc = "Run available linters",
        callback = function()
          for _, name in ipairs(lint.linters_by_ft[vim.bo.filetype] or {}) do
            if vim.fn.executable(name) == 1 then
              lint.try_lint(name)
            end
          end
        end,
      })
    end,
  },
}
