local completers = require("kubectl.commands.completers")
local registry = require("kubectl.commands")

local M = {}

---@type CommandSpec
M.spec = {
  name = "get",
  flags = completers.get_flags(),

  execute = function(args)
    local view = require("kubectl.views")
    if #args == 1 then
      -- Single resource type: use the interactive view
      local resource_type = args[1]
      view.resource_or_fallback(resource_type)
    else
      -- Multiple args or flags: pass through to kubectl
      local cmd_args = vim.list_extend({ "get" }, args)
      view.UserCmd(cmd_args)
    end
  end,

  complete = function(positional, _)
    -- Complete resource types for first positional arg
    if #positional <= 1 then
      return completers.resources()
    end
    return {}
  end,
}

registry.register(M.spec)

return M
