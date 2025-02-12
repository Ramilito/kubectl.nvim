local crds_view = require("kubectl.views.crds")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(crds_view.Draw)
  end
end

init()
