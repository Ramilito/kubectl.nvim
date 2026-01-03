local registry = require("kubectl.commands")

local M = {}

---@type CommandSpec
M.spec = {
  name = "api-resources",
  flags = {
    {
      name = "namespaced",
      takes_value = true,
      complete = function()
        return { "true", "false" }
      end,
    },
    { name = "verbs", takes_value = true },
    { name = "api-group", takes_value = true },
    {
      name = "output",
      short = "o",
      takes_value = true,
      complete = function()
        return { "wide", "name" }
      end,
    },
  },

  execute = function(_)
    local api_resources = require("kubectl.resources.api-resources")
    api_resources.View()
  end,

  complete = function(_, _)
    return {}
  end,
}

registry.register(M.spec)

return M
