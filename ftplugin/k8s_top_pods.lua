local loop = require("kubectl.utils.loop")
local pods_top_view = require("kubectl.views.top_pods")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(pods_top_view.View)
  end
end

init()
