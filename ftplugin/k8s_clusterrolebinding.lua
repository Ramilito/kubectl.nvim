local clusterrolebinding_view = require("kubectl.views.clusterrolebinding")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(clusterrolebinding_view.Draw)
  end
end

init()
