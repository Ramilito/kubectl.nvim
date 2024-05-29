local tables = require("kubectl.view.tables")

local M = {}

local actions = require("kubectl.actions")

function M.filter()
  local hints = tables.generateHints({
    { key = "<enter>", desc = "apply" },
  }, false, false)
  actions.filter_buffer("Filter: ", "k8s_filter", { title = "Filter", hints = hints })
end

return M
