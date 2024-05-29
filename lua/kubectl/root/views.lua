local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

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
  actions.new_buffer(results, "k8s_root", { is_float = false, hints = hints })
end

return M
