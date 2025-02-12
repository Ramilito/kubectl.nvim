local loop = require("kubectl.utils.loop")
local replicaset_view = require("kubectl.views.replicasets")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(replicaset_view.Draw)
  end
end

init()
