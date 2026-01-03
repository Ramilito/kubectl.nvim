local completers = require("kubectl.commands.completers")
local registry = require("kubectl.commands")

local M = {}

--- Apply current buffer contents to the cluster with confirmation
function M.execute_apply()
  local buffers = require("kubectl.actions.buffers")
  local commands = require("kubectl.actions.commands")
  local manager = require("kubectl.resource_manager")

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local file_name = vim.api.nvim_buf_get_name(0)
  local content = table.concat(lines, "\n")

  local builder = manager.get_or_create("kubectl_apply")

  commands.shell_command_async("kubectl", { "diff", "-f", "-" }, function(data)
    builder.data = data
    builder.splitData()
    vim.schedule(function()
      local win_config
      builder.buf_nr, win_config = buffers.confirmation_buffer("Apply " .. file_name .. "?", "diff", function(confirm)
        if confirm then
          commands.shell_command_async("kubectl", { "apply", "-f", "-" }, nil, nil, nil, { stdin = content })
        end
      end)

      if #builder.data == 1 then
        table.insert(builder.data, "[Info]: No changes found when running diff.")
      end
      local confirmation = "[y]es [n]o:"
      local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

      table.insert(builder.data, padding .. confirmation)
      builder.displayContentRaw()
    end)
  end, nil, nil, { stdin = content })
end

---@type CommandSpec
M.spec = {
  name = "apply",
  flags = vim.list_extend({
    { name = "filename", short = "f", takes_value = true },
    {
      name = "dry-run",
      takes_value = true,
      complete = function()
        return { "none", "client", "server" }
      end,
    },
    { name = "force", takes_value = false },
    { name = "prune", takes_value = false },
  }, completers.common_flags),

  execute = function(_)
    M.execute_apply()
  end,

  complete = function(_, _)
    return {}
  end,
}

registry.register(M.spec)

return M
