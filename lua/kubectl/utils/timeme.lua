local M = {}
M.startTime = nil

M.start = function()
  M.startTime = vim.fn.reltime()
end

M.stop = function()
  local elapsed_time = vim.fn.reltimefloat(vim.fn.reltime(M.startTime))
  -- local log = require("kubectl.log")
  vim.print("Execution time: seconds", elapsed_time)
end

return M
