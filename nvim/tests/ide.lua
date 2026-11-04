-- Headless IDE test. Run with throwaway XDG dirs and the config linked at
-- $XDG_CONFIG_HOME/nvim:
--   DOTFILES_NVIM_OFFLINE=1 nvim --headless -l nvim/tests/ide.lua   (core checks, plugin checks skip)
--   nvim --headless -l nvim/tests/ide.lua                           (plugins restored: nothing skips)
-- It never clones or installs anything (DOTFILES_NVIM_NO_INSTALL=1, below), so
-- restore first with `nvim --headless "+Lazy! restore" +qa` and, after the run,
-- check that nvim/lazy-lock.json is unchanged. Also run it with HERDR_ENV=1.
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
vim.env.DOTFILES_NVIM_NO_INSTALL = "1" -- inherited by the child nvims too
vim.go.loadplugins = true -- off under -l, and lazy.nvim does nothing without it
vim.opt.rtp:prepend(config)
dofile(config .. "/init.lua")

-- Run a child nvim and return its combined output. `extra` entries are added to
-- the parent environment; `path` replaces PATH when given.
local function child(args, path, extra)
  local cmd = { vim.v.progpath, "--headless" }
  vim.list_extend(cmd, args)
  local env = vim.tbl_extend("force", { PATH = path, HOME = vim.env.HOME }, extra or {})
  local res = vim.system(cmd, { text = true, env = (path or extra) and env or nil }):wait(30000)
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

-- Old Neovim: warn once, never reach the plugin layer. Offline mode is switched
-- off in the child, so config.lazy would run if init.lua got that far; the
-- preloads record any attempt to require it (or lazy.nvim itself).
do
  local text = child({
    "--cmd",
    "lua local has = vim.fn.has; vim.fn.has = function(f) if f == 'nvim-0.12' then return 0 end return has(f) end"
      .. "; _G.required = {}; for _, m in ipairs({ 'config.lazy', 'lazy' }) do"
      .. " package.preload[m] = function() table.insert(_G.required, m); return {} end end",
    "-c",
    "lua io.stdout:write('required=[' .. table.concat(_G.required, ',') .. ']\\n')",
    "-c",
    "qa!",
  }, nil, { DOTFILES_NVIM_OFFLINE = "0" })
  local warnings = select(2, text:gsub("needs Neovim 0%.12%+", ""))
  check("old nvim warns once", warnings == 1, text)
  check("old nvim loads no plugins", text:find("required=[]", 1, true) ~= nil, text)
end

-- The plugins the config is meant to have. Adding or dropping one is a change to
-- this list, the specs and the lockfile together.
local allowed = {
  "blink.cmp",
  "conform.nvim",
  "fzf-lua",
  "gitsigns.nvim",
  "gruvbox.nvim",
  "lazy.nvim",
  "lazydev.nvim",
  "lualine.nvim",
  "mini.nvim",
  "neotest",
  "neotest-golang",
  "neotest-python",
  "nvim-dap",
  "nvim-dap-go",
  "nvim-dap-python",
  "nvim-dap-ui",
  "nvim-lint",
  "nvim-lspconfig",
  "nvim-nio",
  "nvim-treesitter",
  "nvim-treesitter-textobjects",
  "oil.nvim",
  "plenary.nvim",
  "trouble.nvim",
  "vim-tmux-navigator",
  "which-key.nvim",
}

-- Plugins: only checked when lazy.nvim is loaded.
local function plugin_checks()
  local lazy_config = require("lazy.core.config")
  local plugins = require("lazy").plugins()
  local names = {} -- every spec, including ones disabled by cond (HERDR_ENV=1)
  for name in pairs(lazy_config.spec.disabled) do
    names[name] = true
  end

  check(
    "lazy spec has no errors",
    #lazy_config.spec.notifs == 0,
    vim.inspect(lazy_config.spec.notifs)
  )
  for _, plugin in ipairs(plugins) do
    names[plugin.name] = true
    check("installed " .. plugin.name, plugin._.installed == true, "not installed")
  end

  -- blink must be up before any LSP client starts, so its capabilities reach them.
  check("blink loaded at startup", package.loaded["blink.cmp"] ~= nil, "not loaded yet")
  local star = vim.lsp.config["*"] or {}
  local completion =
    vim.tbl_get(star, "capabilities", "textDocument", "completion", "completionItem")
  check(
    "lsp capabilities from blink",
    completion ~= nil and completion.snippetSupport == true,
    vim.inspect(completion)
  )

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
  for _, name in ipairs(allowed) do
    check("spec has " .. name, names[name] == true, "no spec")
    check("lockfile has a row for " .. name, lock[name] ~= nil, "no row")
  end
  local allow = {}
  for _, name in ipairs(allowed) do
    allow[name] = true
  end
  for name in pairs(names) do
    check("spec is allowed: " .. name, allow[name] == true, "not in the allowlist")
  end
  for name in pairs(lock) do
    check("lockfile row is allowed: " .. name, allow[name] == true, "not in the allowlist")
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
