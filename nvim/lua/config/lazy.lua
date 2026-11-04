if vim.env.DOTFILES_NVIM_OFFLINE == "1" then
  return
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local ok, out = false, "git is not installed"
  if vim.fn.executable("git") == 1 then
    out = vim.fn.system({
      "git",
      "clone",
      "--filter=blob:none",
      "--branch=v11.17.5",
      "https://github.com/folke/lazy.nvim.git",
      lazypath,
    })
    ok = vim.v.shell_error == 0
  end
  if not ok then
    local reason = vim.trim(out):match("[^\n]*$")
    vim.api.nvim_echo({
      {
        "nvim: could not install lazy.nvim (" .. reason .. "); continuing without plugins",
        "WarningMsg",
      },
    }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = { { import = "plugins" } },
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
  checker = { enabled = false },
  change_detection = { notify = false },
})
