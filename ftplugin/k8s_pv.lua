local loop = require("kubectl.utils.loop")
local pv_view = require("kubectl.views.pv")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(pv_view.Draw)
  end
end

init()
