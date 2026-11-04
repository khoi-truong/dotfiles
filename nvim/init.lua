vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

if vim.fn.has("nvim-0.12") == 0 then
  local v = vim.version()
  vim.api.nvim_echo({
    {
      ("nvim config needs Neovim 0.12+, this is %d.%d.%d"):format(v.major, v.minor, v.patch),
      "WarningMsg",
    },
  }, true, {})
  require("config.options")
  return
end

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lsp")
require("config.lazy")
