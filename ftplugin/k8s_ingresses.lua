local ingresses_view = require("kubectl.views.ingresses")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(ingresses_view.Draw)
  end
end

init()
