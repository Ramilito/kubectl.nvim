local actions = require("kubectl.actions.actions")
local tables = require("kubectl.utils.tables")

local M = {}

function M.filter()
  local hints = tables.generateHeader({
    { key = "<enter>", desc = "apply" },
    { key = "<q>", desc = "close" },
  }, false, false)
  actions.filter_buffer("Filter: ", "k8s_filter", { title = "Filter", hints = hints })
end

return M
