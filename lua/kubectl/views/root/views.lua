local tables = require("kubectl.utils.tables")
local actions = require("kubectl.actions.actions")

local M = {}

function M.Root()
  local results = {
    "Deployments",
    "Events",
    "Nodes",
    "Secrets",
    "Services",
  }
  local hints = tables.generateHints({
    { key = "<enter>", desc = "Select" },
  }, true, true)
  actions.buffer(results, "k8s_root", { hints = hints })
end

return M
