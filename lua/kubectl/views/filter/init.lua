local actions = require("kubectl.actions.actions")
local tables = require("kubectl.utils.tables")

local M = {}

function M.filter()
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "apply" },
    { key = "<q>", desc = "close" },
  }, false, false)
  actions.filter_buffer("Filter: ", marks, "k8s_filter", { title = "Filter", header = { data = header, marks = marks } })
end

return M
