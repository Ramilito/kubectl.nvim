local loop = require("kubectl.utils.loop")
local node_view = require("kubectl.views.nodes")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(node_view.Draw)
  end
end

init()
