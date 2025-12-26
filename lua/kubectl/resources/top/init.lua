local dashboard = require("kubectl.views.dashboard")
local M = {}

function M.View()
  return dashboard.top()
end

return M
