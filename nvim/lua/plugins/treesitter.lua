local languages = {
  "bash",
  "go",
  "python",
  "rust",
  "swift",
  "typescript",
  "json",
  "yaml",
  "toml",
  "markdown_inline",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    config = function()
      -- Compiling parsers needs the tree-sitter CLI, and is skipped headless.
      if vim.fn.executable("tree-sitter") == 1 and #vim.api.nvim_list_uis() > 0 then
        require("nvim-treesitter").install(languages)
      end
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("dotfiles-treesitter", { clear = true }),
        desc = "Start tree-sitter highlight and indent",
        callback = function(args)
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-treesitter-textobjects").setup({ select = { lookahead = true } })
      local select = require("nvim-treesitter-textobjects.select")
      for lhs, query in pairs({
        af = "@function.outer",
        ["if"] = "@function.inner",
        ac = "@class.outer",
        ic = "@class.inner",
      }) do
        vim.keymap.set({ "x", "o" }, lhs, function()
          select.select_textobject(query, "textobjects")
        end, { desc = "Select " .. query })
      end
    end,
  },
}
