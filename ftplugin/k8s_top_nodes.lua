local loop = require("kubectl.utils.loop")
local nodes_top_view = require("kubectl.views.top_nodes")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(nodes_top_view.View)
  end
end

init()
