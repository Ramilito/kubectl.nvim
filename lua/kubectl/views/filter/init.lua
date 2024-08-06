local buffers = require("kubectl.actions.buffers")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.filter()
  local buf = buffers.filter_buffer("k8s_filter", { title = "Filter", header = { data = {} } })
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "apply" },
    { key = "<q>", desc = "close" },
  }, false, false)

  vim.api.nvim_buf_set_lines(buf, 0, #header, false, header)
  vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Filter: " .. state.getFilter(), "" })

  buffers.apply_marks(buf, marks, header)
end

return M
