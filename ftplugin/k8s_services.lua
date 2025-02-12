local loop = require("kubectl.utils.loop")
local service_view = require("kubectl.views.services")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(service_view.Draw)
  end
end

init()
