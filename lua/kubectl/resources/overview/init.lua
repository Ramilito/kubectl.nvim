local dashboard = require("kubectl.views.dashboard")
local M = {}

function M.View()
  return dashboard.overview()
end

return M
