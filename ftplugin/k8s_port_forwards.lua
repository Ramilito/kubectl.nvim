local commands = require("kubectl.actions.commands")
local tables = require("kubectl.utils.tables")

local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "gk", "", {
    noremap = true,
    silent = true,
    desc = "Kill port forward",
    callback = function()
      local pid, resource = tables.getCurrentSelection(1, 2)
      vim.notify("Killing port forward for resource " .. resource .. " with pid: " .. pid)

      commands.shell_command_async("sh", { "-c", "kill " .. pid }, function()
        vim.schedule(function()
          local line_number = vim.api.nvim_win_get_cursor(0)[1]
          vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, {})
        end)
      end)
    end,
  })
end

local function init()
  set_keymaps(0)
end

init()
