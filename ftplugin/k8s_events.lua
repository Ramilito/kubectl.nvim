local event_view = require("kubectl.views.events")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(event_view.Draw)
  end
end

init()
