local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(overview_view.View, { interval = 30000 })
  end
end

init()
