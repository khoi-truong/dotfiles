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
vim.go.loadplugins = true -- off under -l, and lazy.nvim does nothing without it
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
local function plugin_checks()
  local lazy_config = require("lazy.core.config")
  local plugins = require("lazy").plugins()
  local names = {}

  check(
    "lazy spec has no errors",
    #lazy_config.spec.notifs == 0,
    vim.inspect(lazy_config.spec.notifs)
  )
  for _, plugin in ipairs(plugins) do
    names[plugin.name] = true
    check("installed " .. plugin.name, plugin._.installed == true, "not installed")
  end

  local modules = {
    "gruvbox",
    "lualine",
    "which-key",
    "mini.ai",
    "mini.surround",
    "mini.pairs",
    "mini.icons",
    "fzf-lua",
    "oil",
    "nvim-treesitter",
    "nvim-treesitter-textobjects",
    "lspconfig",
    "lazydev",
    "blink.cmp",
    "conform",
    "lint",
    "gitsigns",
    "trouble",
    "dap",
    "dapui",
    "nio",
    "dap-python",
    "dap-go",
    "neotest",
    "plenary",
    "neotest-python",
    "neotest-golang",
  }
  for _, module in ipairs(modules) do
    local loaded, err = pcall(require, module)
    check("require " .. module, loaded, tostring(err))
  end

  check("colorscheme gruvbox", vim.g.colors_name == "gruvbox", tostring(vim.g.colors_name))

  local maps = {
    [" ff"] = "n",
    [" fg"] = "n",
    [" fb"] = "n",
    ["-"] = "n",
    [" cf"] = "n",
    [" xx"] = "n",
    [" db"] = "n",
    [" dc"] = "n",
    [" tt"] = "n",
    [" gb"] = "n",
  }
  for lhs, mode in pairs(maps) do
    local map = vim.fn.maparg(lhs, mode, false, true)
    check(
      "map " .. lhs .. " desc",
      type(map.desc) == "string" and map.desc ~= "",
      "missing map or desc"
    )
  end

  local conform = require("conform")
  check("conform lua formatter", conform.formatters_by_ft.lua[1] == "stylua")

  -- Language files in a PATH with no language tools raise nothing.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local script = dir .. "/open.lua"
  vim.uv.fs_symlink(vim.fn.exepath("git"), dir .. "/git") -- gitsigns needs git, which is not a language tool
  local files = {}
  for _, name in ipairs({ "a.go", "a.py", "a.swift", "a.lua" }) do
    files[#files + 1] = dir .. "/" .. name
    vim.fn.writefile({ "x" }, dir .. "/" .. name)
  end
  vim.fn.writefile({
    "local before = vim.fn.execute('messages')",
    "vim.v.errmsg = ''",
    "for _, f in ipairs(" .. vim.inspect(files) .. ") do",
    "  vim.cmd('edit ' .. f)",
    "  vim.cmd('silent write')",
    "  vim.cmd('doautocmd FileType')",
    "end",
    "vim.wait(500)",
    "local after = vim.fn.execute('messages')",
    "io.stdout:write(('errmsg=[%s]\\n'):format(vim.v.errmsg))",
    "io.stdout:write(('messages-same=%s\\n'):format(tostring(before == after)))",
    "io.stdout:write('messages-after=' .. after .. '\\n')",
  }, script)
  local text = child({ "-c", "luafile " .. script, "-c", "qa!" }, dir)
  check("language files raise no error", text:find("errmsg=[]", 1, true) ~= nil, text)
  check("language files add no messages", text:find("messages-same=true", 1, true) ~= nil, text)
  vim.fn.delete(dir, "rf")

  local lock = vim.json.decode(table.concat(vim.fn.readfile(config .. "/lazy-lock.json"), "\n"))
  check("lockfile has no herdr-splits", lock["herdr-splits.nvim"] == nil)
  for name in pairs(lock) do
    check("lockfile row has a spec: " .. name, names[name] == true, "no spec")
  end
  for name in pairs(names) do
    check("spec has a lockfile row: " .. name, lock[name] ~= nil, "no row")
  end
end

if package.loaded.lazy then
  plugin_checks()
else
  skip("plugin checks", "plugins not installed")
end

if failed then
  os.exit(1)
end
os.exit(0)
