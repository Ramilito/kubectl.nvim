local M = {}
M.startTime = nil

M.start = function()
  M.startTime = vim.fn.reltime()
end

M.stop = function()
  local elapsed_time = vim.fn.reltimefloat(vim.fn.reltime(M.startTime))
  print("Execution time: " .. elapsed_time .. " seconds")
end

return M
