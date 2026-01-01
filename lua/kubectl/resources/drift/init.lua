local drift = require("kubectl.views.drift")
local M = {}

function M.View()
  return drift.open()
end

return M
