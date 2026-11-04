-- Headless IDE test. Run with throwaway XDG dirs and the config linked at
-- $XDG_CONFIG_HOME/nvim:
--   DOTFILES_NVIM_OFFLINE=1 nvim --headless -l nvim/tests/ide.lua   (core checks, plugin checks skip)
--   nvim --headless -l nvim/tests/ide.lua                           (plugins restored: nothing skips)
local failed = false

local function out(line)
  io.stdout:write(line .. "\n")
end
local function ok(name)
  out("ok " .. name)
end
local function fail(name, why)
  failed = true
  out(("FAIL %s: %s"):format(name, why))
end
local function skip(name, why)
  out(("skip %s: %s"):format(name, why))
end
local function check(name, cond, why)
  if cond then
    ok(name)
  else
    fail(name, why or "false")
  end
end

local config = vim.fn.stdpath("config")
vim.opt.rtp:prepend(config)
dofile(config .. "/init.lua")

-- Run a child nvim and return its combined output. `env` entries are added to
-- the parent environment; `path` replaces PATH when given.
local function child(args, path)
  local cmd = { vim.v.progpath, "--headless" }
  vim.list_extend(cmd, args)
  local env = { PATH = path, HOME = vim.env.HOME }
  local res = vim.system(cmd, { text = true, env = path and env or nil }):wait(30000)
  return (res.stdout or "") .. (res.stderr or ""), res.code
end

-- Core: leader, options, autocmds, keymaps.
check("leader", vim.g.mapleader == " ", "mapleader is " .. vim.inspect(vim.g.mapleader))
check("maplocalleader", vim.g.maplocalleader == "\\")

local options = {
  number = true,
  relativenumber = true,
  signcolumn = "yes",
  undofile = true,
  ignorecase = true,
  smartcase = true,
  expandtab = true,
  shiftwidth = 2,
  splitright = true,
  splitbelow = true,
  scrolloff = 8,
  updatetime = 250,
  termguicolors = true,
}
for name, want in pairs(options) do
  check("option " .. name, vim.o[name] == want, ("got %s"):format(vim.inspect(vim.o[name])))
end
check(
  "option clipboard",
  vim.o.clipboard == "unnamedplus",
  ("got %s"):format(vim.inspect(vim.o.clipboard))
)

check(
  "augroup dotfiles",
  #vim.api.nvim_get_autocmds({ group = "dotfiles" }) > 0,
  "no autocmds in group dotfiles"
)

for _, lhs in ipairs({ "<Esc>", " w", " q", "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  local map = vim.fn.maparg(lhs, "n", false, true)
  check("map " .. lhs .. " desc", type(map.desc) == "string" and map.desc ~= "", "missing desc")
end

-- LSP PATH gate: only a fake gopls is on PATH.
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local fake = dir .. "/gopls"
  vim.fn.writefile({ "#!/bin/sh", "exit 0" }, fake)
  vim.uv.fs_chmod(fake, 493)
  local text = child({
    "-c",
    "lua io.stdout:write(('gopls=%s rust=%s\\n'):format("
      .. "tostring(vim.lsp.is_enabled('gopls')),"
      .. "tostring(vim.lsp.is_enabled('rust_analyzer'))))",
    "-c",
    "qa!",
  }, dir)
  check("lsp gate enables gopls", text:find("gopls=true", 1, true) ~= nil, text)
  check("lsp gate skips rust_analyzer", text:find("rust=false", 1, true) ~= nil, text)
  vim.fn.delete(dir, "rf")
end

-- Opening a .go file with no language tools on PATH raises nothing.
do
  local empty = vim.fn.tempname()
  vim.fn.mkdir(empty, "p")
  local scratch = empty .. "/main.go"
  vim.fn.writefile({ "package main" }, scratch)
  local text = child({
    "-c",
    "edit " .. scratch,
    "-c",
    "lua io.stdout:write('errmsg=[' .. vim.v.errmsg .. ']\\n')",
    "-c",
    "qa!",
  }, empty)
  check("open .go adds no v:errmsg", text:find("errmsg=[]", 1, true) ~= nil, text)
  vim.fn.delete(empty, "rf")
end

-- Old Neovim: warn once, load no plugins.
do
  local text = child({
    "--cmd",
    "lua local has = vim.fn.has; vim.fn.has = function(f) if f == 'nvim-0.12' then return 0 end return has(f) end",
    "-c",
    "lua io.stdout:write('lazy=' .. tostring(package.loaded.lazy ~= nil) .. '\\n')",
    "-c",
    "qa!",
  })
  local warnings = select(2, text:gsub("needs Neovim 0%.12%+", ""))
  check("old nvim warns once", warnings == 1, text)
  check("old nvim loads no plugins", text:find("lazy=false", 1, true) ~= nil, text)
end

-- Plugins: only checked when lazy.nvim is loaded.
local plugin_checks = { "plugins loaded" }
if package.loaded.lazy then
  -- Filled in by the plugin layer.
else
  for _, name in ipairs(plugin_checks) do
    skip(name, "plugins not installed")
  end
end

if failed then
  os.exit(1)
end
os.exit(0)
