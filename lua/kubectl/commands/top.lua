local registry = require("kubectl.commands")

local M = {}

---@type CommandSpec
M.spec = {
  name = "top",
  flags = {},

  execute = function(args)
    local dashboard = require("kubectl.views.dashboard")
    -- Currently dashboard.top() shows both pods and nodes
    -- The subcommand argument is accepted but not differentiated
    if #args >= 1 then
      local subcommand = args[1]
      if subcommand == "pods" or subcommand == "nodes" then
        -- TODO: Support separate pods/nodes views when backend supports it
        dashboard.top()
      else
        -- Unknown subcommand, still show top
        dashboard.top()
      end
    else
      dashboard.top()
    end
  end,

  complete = function(positional, _)
    if #positional <= 1 then
      return { "pods", "nodes" }
    end
    return {}
  end,
}

registry.register(M.spec)

return M
