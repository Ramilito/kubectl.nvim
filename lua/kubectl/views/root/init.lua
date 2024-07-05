local buffers = require("kubectl.actions.buffers")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View()
  local results = {
    "Deployments",
    "Events",
    "Nodes",
    "Secrets",
    "Services",
    "Configmaps",
  }
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "Select" },
  }, true, true)
  buffers.buffer(results, {}, "k8s_root", { title = "Root", header = { data = header, marks = marks } })
end

return M
