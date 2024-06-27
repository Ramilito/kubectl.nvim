local actions = require("kubectl.actions.actions")
local tables = require("kubectl.utils.tables")

local M = {}

function M.Root()
  local results = {
    "Deployments",
    "Events",
    "Nodes",
    "Secrets",
    "Services",
    "Configmaps",
  }
  local hints = tables.generateHints({
    { key = "<enter>", desc = "Select" },
  }, true, true)
  actions.buffer(results, {}, "k8s_root", { title = "Root", hints = hints })
end

return M
