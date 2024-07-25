local commands = require("kubectl.actions.commands")
local tables = require("kubectl.utils.tables")
local views = require("kubectl.views")

local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "gk", "", {
    noremap = true,
    silent = true,
    desc = "Kill port forward",
    callback = function()
      local pid, resource = tables.getCurrentSelection(1, 2)
      vim.notify("Killing port forward for resource " .. resource .. " with pid: " .. pid)
      commands.shell_command("kill", { pid })
      views.PortForwards()
    end,
  })
end

local function init()
  set_keymaps(0)
end

init()
