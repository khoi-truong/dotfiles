-- Each group is a list of alternatives; the first whose binary is on PATH wins.
-- cmd/filetypes/root_markers are the fallback used when nvim-lspconfig's own
-- lsp/*.lua config is not on the runtimepath (no plugins, or not loaded yet).
local servers = {
  {
    {
      name = "lua_ls",
      cmd = { "lua-language-server" },
      filetypes = { "lua" },
      root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
    },
  },
  {
    {
      name = "basedpyright",
      cmd = { "basedpyright-langserver", "--stdio" },
      filetypes = { "python" },
      root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
    },
    {
      name = "pyright",
      cmd = { "pyright-langserver", "--stdio" },
      filetypes = { "python" },
      root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
    },
  },
  {
    {
      name = "ruff",
      cmd = { "ruff", "server" },
      filetypes = { "python" },
      root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
    },
  },
  {
    {
      name = "gopls",
      cmd = { "gopls" },
      filetypes = { "go", "gomod", "gowork", "gotmpl" },
      root_markers = { "go.work", "go.mod", ".git" },
    },
  },
  {
    {
      name = "rust_analyzer",
      cmd = { "rust-analyzer" },
      filetypes = { "rust" },
      root_markers = { "Cargo.toml", ".git" },
    },
  },
  {
    {
      name = "ts_ls",
      cmd = { "typescript-language-server", "--stdio" },
      filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
      root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
    },
  },
  {
    {
      name = "bashls",
      cmd = { "bash-language-server", "start" },
      filetypes = { "sh", "bash", "zsh" },
      root_markers = { ".git" },
    },
  },
  {
    {
      name = "jsonls",
      cmd = { "vscode-json-language-server", "--stdio" },
      filetypes = { "json", "jsonc" },
      root_markers = { ".git" },
    },
  },
  {
    {
      name = "yamlls",
      cmd = { "yaml-language-server", "--stdio" },
      filetypes = { "yaml" },
      root_markers = { ".git" },
    },
  },
  {
    {
      name = "marksman",
      cmd = { "marksman", "server" },
      filetypes = { "markdown" },
      root_markers = { ".marksman.toml", ".git" },
    },
  },
  {
    {
      name = "starpls",
      cmd = { "starpls" },
      filetypes = { "bzl" },
      root_markers = { "WORKSPACE", "MODULE.bazel", ".git" },
    },
  },
  {
    {
      name = "sourcekit",
      cmd = { "sourcekit-lsp" },
      filetypes = { "swift" },
      root_markers = { "Package.swift", ".git" },
    },
  },
}

for _, group in ipairs(servers) do
  for _, server in ipairs(group) do
    local configured = vim.lsp.config[server.name] or {}
    local cmd = type(configured.cmd) == "table" and configured.cmd or server.cmd
    if configured.cmd == nil then
      vim.lsp.config(server.name, {
        cmd = server.cmd,
        filetypes = server.filetypes,
        root_markers = server.root_markers,
      })
    end
    if vim.fn.executable(cmd[1]) == 1 then
      vim.lsp.enable(server.name)
      break
    end
  end
end

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("dotfiles-lsp", { clear = true }),
  desc = "LSP buffer-local maps",
  callback = function(args)
    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
    end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
  end,
})
