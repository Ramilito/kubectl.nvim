local M = { times = {} }

M.start = function(name)
  M.times[name] = vim.fn.reltime()
end

M.stop = function(name)
  local elapsed_time = vim.fn.reltimefloat(vim.fn.reltime(M.times[name]))
  -- local log = require("kubectl.log")
  print(string.format("Execution time of %s: %.3f seconds", name, elapsed_time))
end

return M
