local loop = require("kubectl.utils.loop")
local pvc_view = require("kubectl.views.pvc")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(pvc_view.Draw)
  end
end

init()
