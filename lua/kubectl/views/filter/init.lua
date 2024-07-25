local buffers = require("kubectl.actions.buffers")
local tables = require("kubectl.utils.tables")

local M = {}

function M.filter()
  buffers.filter_buffer(
    "Filter: ",
    {},
    "k8s_filter",
    { title = "Filter", header = { data = {} } }
  )
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "apply" },
    { key = "<q>", desc = "close" },
  }, false, false)
  buffers.filter_buffer(
    "Filter: ",
    marks,
    "k8s_filter",
    { title = "Filter", header = { data = header, marks = marks } }
  )
end

return M
