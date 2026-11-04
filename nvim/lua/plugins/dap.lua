local function ok(cmd)
  return vim.fn.executable(cmd[1]) == 1 and vim.system(cmd):wait().code == 0
end

return {
  {
    "mfussenegger/nvim-dap",
    keys = {
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "Continue",
      },
    },
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "mfussenegger/nvim-dap-python",
      "leoluz/nvim-dap-go",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      dapui.setup()
      dap.listeners.before.attach.dapui_config = dapui.open
      dap.listeners.before.launch.dapui_config = dapui.open
      dap.listeners.before.event_terminated.dapui_config = dapui.close
      dap.listeners.before.event_exited.dapui_config = dapui.close

      if ok({ "python3", "-c", "import debugpy" }) then
        require("dap-python").setup("python3")
      end
      if vim.fn.executable("dlv") == 1 then
        require("dap-go").setup()
      end
      if ok({ "xcrun", "-f", "lldb-dap" }) then
        dap.adapters.lldb = {
          type = "executable",
          command = vim.trim(vim.system({ "xcrun", "-f", "lldb-dap" }):wait().stdout),
          name = "lldb",
        }
        dap.configurations.swift = {
          {
            name = "Launch",
            type = "lldb",
            request = "launch",
            program = function()
              return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
            end,
            cwd = "${workspaceFolder}",
          },
        }
      end
    end,
  },
}
