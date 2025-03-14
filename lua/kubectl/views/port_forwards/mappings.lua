local commands = require("kubectl.actions.commands")
local mappings = require("kubectl.mappings")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.delete)"] = {
    noremap = true,
    silent = true,
    desc = "Delete port forward",
    callback = function()
      local pid, resource = tables.getCurrentSelection(1, 2)
      vim.notify("Deleting port forward for resource " .. resource .. " with pid: " .. pid)

      commands.shell_command_async("sh", { "-c", "kill " .. pid }, function()
        vim.schedule(function()
          local line_number = vim.api.nvim_win_get_cursor(0)[1]
          vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, {})
        end)
      end)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
end

return M
