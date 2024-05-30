local tables = require("kubectl.utils.tables")
local actions = require("kubectl.actions.actions")

local M = {}

function M.filter()
  local hints = tables.generateHints({
    { key = "<enter>", desc = "apply" },
  }, false, false)
  actions.filter_buffer("Filter: ", "k8s_filter", { title = "Filter", hints = hints })
end

return M
