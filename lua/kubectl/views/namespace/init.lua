local actions = require("kubectl.actions.actions")
local tables = require("kubectl.utils.tables")

local M = {}

function M.pick()
  local hints = tables.generateHints({
    { key = "<enter>", desc = "apply" },
  }, false, false)
  actions.namespace_buffer("Namespace: ", "k8s_namespace", { title = "Namespace", hints = hints })
end

return M
