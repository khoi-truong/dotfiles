if vim.env.DOTFILES_NVIM_OFFLINE == "1" then
  return
end

local function warn(msg)
  vim.api.nvim_echo({ { msg, "WarningMsg" } }, true, {})
end

local function last_line(text)
  return vim.trim(text):match("[^\n]*$")
end

-- Test-only: never clone or install anything.
local no_install = vim.env.DOTFILES_NVIM_NO_INSTALL == "1"
local timeout = tonumber(vim.env.DOTFILES_NVIM_CLONE_TIMEOUT_MS) or 60000

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
-- init.lua, not the directory: an interrupted clone leaves the directory behind.
if not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
  if no_install then
    return
  end
  local ok, reason = false, "git is not installed"
  if vim.fn.executable("git") == 1 then
    vim.fn.delete(lazypath, "rf")
    local res = vim
      .system({
        "git",
        "clone",
        "--filter=blob:none",
        "--branch=v11.17.5",
        "https://github.com/folke/lazy.nvim.git",
        lazypath,
      }, { text = true })
      :wait(timeout)
    ok = res.code == 0
    reason = res.code == 124 and ("timed out after " .. timeout / 1000 .. "s")
      or last_line((res.stderr or "") .. (res.stdout or ""))
    if not ok then
      vim.fn.delete(lazypath, "rf")
    end
  end
  if not ok then
    warn("nvim: could not install lazy.nvim (" .. reason .. "); continuing without plugins")
    return
  end
end

local ok, err = pcall(function()
  vim.opt.rtp:prepend(lazypath)
  require("lazy").setup({
    spec = { { "folke/lazy.nvim", version = "*" }, { import = "plugins" } },
    lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
    install = { missing = not no_install },
    checker = { enabled = false },
    change_detection = { notify = false },
  })
end)
if not ok then
  warn(
    "nvim: plugins incomplete ("
      .. last_line(tostring(err))
      .. "); run :Lazy restore with network, or DOTFILES_NVIM_OFFLINE=1"
  )
end
